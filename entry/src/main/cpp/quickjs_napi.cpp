// quickjs_napi.cpp —— QuickJS 鸿蒙 NAPI 封装（JSExecutor 的 C 层）
//
// 职责：
//  1. 创建 JSRuntime/JSContext，注入宿主全局（sendMessage / console / timer / k* 常量 / TextCodec）
//  2. eval 拼接后的 视频扩展脚本
//  3. call(method, argsJson, id)：调用扩展 async 方法，结果经 onResult(id, resultJson) 异步回传
//  4. sendMessage 桥接：JS 侧调用 sendMessage(cmd, json) → 创建 Promise → 调 onRequest(id, cmd, json)
//     ArkTS 处理完成后调 resolve(id, resultJson) → C 层 resolve Promise → 驱动微任务
//
// 线程模型：全部在 ArkTS 主线程（JS 线程）执行，无锁。网络 IO 由 ArkTS 异步完成。

#include "napi/native_api.h"
#include "quickjs.h"
#include "quickjs-libc.h"

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>

// ---------------- 全局状态 ----------------
static JSRuntime* g_rt = nullptr;
static JSContext* g_ctx = nullptr;
static napi_env g_env = nullptr;

// ArkTS 侧注册的回调引用
static napi_ref g_onRequestRef = nullptr; // (id:number, cmd:string, json:string) => void
static napi_ref g_onResultRef = nullptr;  // (id:number, resultJson:string) => void

// 当前 in-flight 的 call id（骨架按串行调用设计；并发需改为 Promise opaque 传 id）
static std::atomic<int64_t> g_callId{0};

// sendMessage 的 pending Promise 表
struct Pending {
    JSValue promise;
    JSValue resolve;
    JSValue reject;
};
static std::map<int64_t, Pending> g_pending;
static std::atomic<int64_t> g_nextId{1};

// ---------------- 宿主前置片段（k* 常量 + TextEncoder/TextDecoder polyfill） ----------------
// 注意：uzUtils.js 里的 k* 常量定义在 // ignore 块内（剥离后消失），宿主必须在此注入；
// QuickJS 不含 TextEncoder/TextDecoder，node-html-parser / buffer 可能用到，故提供 UTF-8 polyfill。
static const char* kHostPreamble =
    "var kIsDesktop=true,kIsAndroid=false,kIsIOS=false,kIsWindows=false,kIsMacOS=false,kIsTV=false,"
    "kLocale='zh-CN',kAppVersion=10000,kIsDebug=false;"
    "function TextEncoder(){}"
    "TextEncoder.prototype.encode=function(s){"
    "  var b=[];"
    "  for(var i=0;i<s.length;i++){"
    "    var c=s.charCodeAt(i);"
    "    if(c<128){b.push(c);}"
    "    else if(c<2048){b.push(192|(c>>6),128|(c&63));}"
    "    else if(c>=55296&&c<=56319&&i+1<s.length){"
    "      var c2=s.charCodeAt(i+1);var cp=((c-55296)<<10)+(c2-56320)+65536;i++;"
    "      b.push(240|(cp>>18),128|((cp>>12)&63),128|((cp>>6)&63),128|(cp&63));"
    "    }else{b.push(224|(c>>12),128|((c>>6)&63),128|(c&63));}"
    "  }"
    "  return new Uint8Array(b);"
    "};"
    "function TextDecoder(){}"
    "TextDecoder.prototype.decode=function(a){"
    "  var b=a instanceof Uint8Array?a:new Uint8Array(a);"
    "  var s='';var i=0;"
    "  while(i<b.length){"
    "    var x=b[i++];"
    "    if(x<128){s+=String.fromCharCode(x);}"
    "    else if((x&224)==192){s+=String.fromCharCode(((x&31)<<6)|(b[i++]&63));}"
    "    else if((x&240)==224){s+=String.fromCharCode(((x&15)<<12)|((b[i++]&63)<<6)|(b[i++]&63));}"
    "    else{var cp=((x&7)<<18)|((b[i++]&63)<<12)|((b[i++]&63)<<6)|(b[i++]&63);"
    "      cp-=65536;s+=String.fromCharCode(55296+(cp>>10),56320+(cp&1023));}"
    "  }"
    "  return s;"
    "};";

// ---------------- 工具 ----------------
static void DrainJobs() {
    if (!g_rt) return;
    JSContext* pctx = nullptr;
    int err;
    while ((err = JS_ExecutePendingJob(g_rt, &pctx)) > 0) {
    }
    if (err < 0 && pctx) {
        JSValue exc = JS_GetException(pctx);
        const char* msg = JS_ToCString(pctx, exc);
        printf("[quickjs] unhandled job error: %s\n", msg ? msg : "?");
        JS_FreeCString(pctx, msg);
        JS_FreeValue(pctx, exc);
    }
}

static std::string QuoteJson(const std::string& s) {
    std::string out = "\"";
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[7];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
                    out += buf;
                } else {
                    out += c;
                }
        }
    }
    out += "\"";
    return out;
}

static void CallOnRequest(int64_t id, const char* cmd, const char* json) {
    if (!g_onRequestRef) return;
    napi_value cb, args[3], global;
    napi_get_reference_value(g_env, g_onRequestRef, &cb);
    napi_create_int64(g_env, id, &args[0]);
    napi_create_string_utf8(g_env, cmd ? cmd : "", NAPI_AUTO_LENGTH, &args[1]);
    napi_create_string_utf8(g_env, json ? json : "", NAPI_AUTO_LENGTH, &args[2]);
    napi_get_global(g_env, &global);
    napi_call_function(g_env, global, cb, 3, args, nullptr);
}

static void CallOnResult(int64_t id, const char* resultJson) {
    if (!g_onResultRef) return;
    napi_value cb, args[2], global;
    napi_get_reference_value(g_env, g_onResultRef, &cb);
    napi_create_int64(g_env, id, &args[0]);
    napi_create_string_utf8(g_env, resultJson ? resultJson : "", NAPI_AUTO_LENGTH, &args[1]);
    napi_get_global(g_env, &global);
    napi_call_function(g_env, global, cb, 2, args, nullptr);
}

// ---------------- QuickJS 侧回调 ----------------
// JS: sendMessage(cmd, json) -> Promise
static JSValue js_sendMessage(JSContext* ctx, JSValueConst this_val, int argc, JSValueConst* argv) {
    const char* cmd = argc > 0 ? JS_ToCString(ctx, argv[0]) : "";
    const char* json = argc > 1 ? JS_ToCString(ctx, argv[1]) : "";

    JSValue resolving_funcs[2];
    JSValue promise = JS_NewPromiseCapability(ctx, resolving_funcs);
    JSValue resolve = resolving_funcs[0];
    JSValue reject = resolving_funcs[1];

    int64_t id = g_nextId.fetch_add(1);
    Pending p;
    // promise 会被 return 给 JS 供 await 持有，同时 pending 表也要持有一份引用，
    // 必须额外 JS_DupValue 一份，否则引用计数少一份 → await/resolve 释放后 double-free 崩溃
    p.promise = JS_DupValue(ctx, promise);
    p.resolve = resolve;
    p.reject = reject;
    g_pending[id] = p;

    CallOnRequest(id, cmd, json);

    JS_FreeCString(ctx, cmd);
    JS_FreeCString(ctx, json);
    return promise;
}

// 扩展方法 resolve 后：把 JSON 字符串结果回传 ArkTS
static JSValue js_on_fulfilled(JSContext* ctx, JSValueConst this_val, int argc, JSValueConst* argv) {
    const char* result = argc > 0 ? JS_ToCString(ctx, argv[0]) : "";
    CallOnResult(g_callId.load(), result);
    JS_FreeCString(ctx, result);
    return JS_UNDEFINED;
}

// 扩展方法 reject 后：把错误包装成 JSON 回传
static JSValue js_on_rejected(JSContext* ctx, JSValueConst this_val, int argc, JSValueConst* argv) {
    const char* msg = argc > 0 ? JS_ToCString(ctx, argv[0]) : "unknown error";
    std::string errJson = "{\"error\":" + QuoteJson(msg ? msg : "unknown error") + "}";
    CallOnResult(g_callId.load(), errJson.c_str());
    JS_FreeCString(ctx, msg);
    return JS_UNDEFINED;
}

// ---------------- 宿主初始化 ----------------
static void SetupGlobals(JSContext* ctx) {
    // console / setTimeout / setInterval 等（quickjs-libc 提供）
    js_std_add_helpers(ctx, 0, nullptr);

    JSValue global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "sendMessage", JS_NewCFunction(ctx, js_sendMessage, "sendMessage", 2));
    JS_FreeValue(ctx, global);

    JSValue ret = JS_Eval(ctx, kHostPreamble, strlen(kHostPreamble), "<host-preamble>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(ret)) {
        JSValue exc = JS_GetException(ctx);
        const char* msg = JS_ToCString(ctx, exc);
        printf("[quickjs] preamble error: %s\n", msg ? msg : "?");
        JS_FreeCString(ctx, msg);
        JS_FreeValue(ctx, exc);
    }
    JS_FreeValue(ctx, ret);
}

// ---------------- NAPI 导出函数 ----------------

// init(onRequest, onResult)
static napi_value NativeInit(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    g_env = env;
    if (g_onRequestRef) napi_delete_reference(env, g_onRequestRef);
    if (g_onResultRef) napi_delete_reference(env, g_onResultRef);
    if (argc >= 2) {
        napi_create_reference(env, argv[0], 1, &g_onRequestRef);
        napi_create_reference(env, argv[1], 1, &g_onResultRef);
    }

    if (!g_rt) {
        g_rt = JS_NewRuntime();
        g_ctx = JS_NewContext(g_rt);
        SetupGlobals(g_ctx);
        printf("[quickjs] runtime initialized\n");
    }
    return nullptr;
}

// load(script)
static napi_value NativeLoad(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (!g_ctx || argc < 1) return nullptr;

    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
    char* script = new char[len + 1];
    napi_get_value_string_utf8(env, argv[0], script, len + 1, &len);

    JSValue ret = JS_Eval(g_ctx, script, len, "<bundle>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(ret)) {
        JSValue exc = JS_GetException(g_ctx);
        const char* msg = JS_ToCString(g_ctx, exc);
        std::string error = msg ? msg : "quickjs load error";
        printf("[quickjs] load error: %s\n", error.c_str());
        JS_FreeCString(g_ctx, msg);
        JS_FreeValue(g_ctx, exc);
        JS_FreeValue(g_ctx, ret);
        delete[] script;
        napi_throw_error(env, "quickjs_load", error.c_str());
        return nullptr;
    }
    JS_FreeValue(g_ctx, ret);
    delete[] script;
    return nullptr;
}

// call(method, argsJson, id)
static napi_value NativeCall(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (!g_ctx || argc < 3) return nullptr;

    char method[128] = {0};
    size_t mlen = 0;
    napi_get_value_string_utf8(env, argv[0], method, sizeof(method), &mlen);

    size_t alen = 0;
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &alen);
    char* argsJson = new char[alen + 1];
    napi_get_value_string_utf8(env, argv[1], argsJson, alen + 1, &alen);

    int64_t id = 0;
    napi_get_value_int64(env, argv[2], &id);
    g_callId.store(id);

    JSValue global = JS_GetGlobalObject(g_ctx);
    JSValue fn = JS_GetPropertyStr(g_ctx, global, method);
    JSValue args = JS_ParseJSON(g_ctx, argsJson, alen, "<args>");
    JSValue ret = JS_Call(g_ctx, fn, JS_UNDEFINED, 1, &args);
    JS_FreeValue(g_ctx, global);
    JS_FreeValue(g_ctx, fn);
    JS_FreeValue(g_ctx, args);
    delete[] argsJson;

    if (JS_IsException(ret)) {
        JSValue exc = JS_GetException(g_ctx);
        const char* msg = JS_ToCString(g_ctx, exc);
        std::string errJson = "{\"error\":" + QuoteJson(msg ? msg : "call error") + "}";
        CallOnResult(id, errJson.c_str());
        JS_FreeCString(g_ctx, msg);
        JS_FreeValue(g_ctx, exc);
        JS_FreeValue(g_ctx, ret);
        return nullptr;
    }

    // ret 应为 async 方法的 Promise，挂 then 回调
    JSValue thenFn = JS_GetPropertyStr(g_ctx, ret, "then");
    if (JS_IsFunction(g_ctx, thenFn)) {
        JSValue onFul = JS_NewCFunction(g_ctx, js_on_fulfilled, "onFulfilled", 1);
        JSValue onRej = JS_NewCFunction(g_ctx, js_on_rejected, "onRejected", 1);
        JSValue thenArgv[2] = {onFul, onRej};
        JSValue thenRet = JS_Call(g_ctx, thenFn, ret, 2, thenArgv);
        JS_FreeValue(g_ctx, thenRet);
        JS_FreeValue(g_ctx, onFul);
        JS_FreeValue(g_ctx, onRej);
    } else {
        // 非 async 方法（防御）：直接把返回值当字符串回传
        const char* s = JS_ToCString(g_ctx, ret);
        CallOnResult(id, s ? s : "");
        JS_FreeCString(g_ctx, s);
    }
    JS_FreeValue(g_ctx, thenFn);
    JS_FreeValue(g_ctx, ret);

    // 驱动微任务到第一个 sendMessage 挂起点
    DrainJobs();
    return nullptr;
}

// resolve(id, resultJson) —— ArkTS 完成 sendMessage 请求后调用
static napi_value NativeResolve(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (!g_ctx || argc < 2) return nullptr;

    int64_t id = 0;
    napi_get_value_int64(env, argv[0], &id);

    size_t jlen = 0;
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &jlen);
    char* json = new char[jlen + 1];
    napi_get_value_string_utf8(env, argv[1], json, jlen + 1, &jlen);

    auto it = g_pending.find(id);
    if (it != g_pending.end()) {
        JSValue v;
        if (jlen == 0) {
            v = JS_NewStringLen(g_ctx, "", 0);
        } else {
            v = JS_ParseJSON(g_ctx, json, jlen, "<resolve>");
            if (JS_IsException(v)) {
                // 非 JSON 文本（如 getEnv 返回的裸字符串）→ 当字符串 resolve
                v = JS_NewStringLen(g_ctx, json, jlen);
            }
        }
        JS_Call(g_ctx, it->second.resolve, JS_UNDEFINED, 1, &v);
        JS_FreeValue(g_ctx, v);
        JS_FreeValue(g_ctx, it->second.resolve);
        JS_FreeValue(g_ctx, it->second.reject);
        JS_FreeValue(g_ctx, it->second.promise);
        g_pending.erase(it);
        DrainJobs();
    }
    delete[] json;
    return nullptr;
}

// dispose()
static napi_value NativeDispose(napi_env env, napi_callback_info info) {
    if (g_ctx) { JS_FreeContext(g_ctx); g_ctx = nullptr; }
    if (g_rt) { JS_FreeRuntime(g_rt); g_rt = nullptr; }
    if (g_onRequestRef) { napi_delete_reference(env, g_onRequestRef); g_onRequestRef = nullptr; }
    if (g_onResultRef) { napi_delete_reference(env, g_onResultRef); g_onResultRef = nullptr; }
    g_pending.clear();
    printf("[quickjs] runtime disposed\n");
    return nullptr;
}

// ---------------- 模块注册 ----------------
EXTERN_C_START
static napi_value Register(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"init", nullptr, NativeInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"load", nullptr, NativeLoad, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"call", nullptr, NativeCall, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resolve", nullptr, NativeResolve, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dispose", nullptr, NativeDispose, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_quickjsModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Register,
    .nm_modname = "quickjs",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterQuickjsModule(void) {
    napi_module_register(&g_quickjsModule);
}
