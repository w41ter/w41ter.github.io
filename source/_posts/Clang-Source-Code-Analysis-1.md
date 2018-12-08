---
title: Clang - Source Code Analysis (1)
date: 2016-05-13 20:21:38
tags: Compile
categories: Clang 源码分析
---

# 前言

读 Clang 源代码是最近一直想做的事情，无奈种种原因一直拖到现在。正好这几天获得了几天喘息时间，便开始了 Clang 源码阅读之旅。

<!-- more -->

Clang 的源代码可以从 github 上的 [Clang](https://github.com/llvm-mirror/clang) 得到。这里我使用的是 Clang 3.9 版本的源代码，如果你使用相近版本，我想问题不会太大。我主要的时间是在 Windows 上工作，所以源代码阅读工作也放到了 Windows 下，毕竟 VS 大法好。具体在 Windows 下如何编译 Clang 请参考 [Clang for windows](http://www.hashcoding.net/2015/12/23/Clang-for-windows/)。

想要研究 Clang 源代码，官方文档便是最好的学习资料，除此之外，你还可以订阅 Clang 邮件组(cfe-dev,cfe-commit)。这里首先建议看一看 [Clang internals Manual](http://clang.llvm.org/docs/InternalsManual.html) 对基础结构有所把握。

我的着手点是来自知乎上的一篇回答 [Clang 真正的前端是什么？](https://www.zhihu.com/question/31425289)。

# 总体结构

Clang 只是一个编译器前端，它获取用户输入，生成语法树，在语义检查和各种诊断后产生 llvm IR。剩下的工作则交给 llvm 完成，而这一切通过 Drive 组织起来。

Clang 默认只进行一遍 parse，你需要通过 Action 来指定完成 parse 后应该干些什么。值得注意的是 Clang 的 Action 穿插在各种 parse 结构中，比如 parse 过程总便对函数声明进行检查。

所以，Clang 的运行流程如下：

1. 解析命令参数，分别为 Analyzer, Migrator, DependencyOutput, Diagnostic, Comment, FileSystem, Frontend, CodeGen, HeaderSearch, LangOpt 等多种类型参数;
2. 根据解析的命令执行相应 Act，进而执行 ParseAST;
3. ParseAST 分为三个部分，前两个部分分别是 ParseTopLevelDecl和 HandleTopLevelDecl;
4. 最后 HandleTranslationUnit 进行检查优化并生成对应的 llvm IR；

下面，我们将通过实际调试来跟踪 Clang 执行流程，首先，写上测试代码：

```
int function(int x, int y) {
    return x + y;
}

int main() {
    int a = 0;
    a = function(a, a);
    return 0;
}
```

保存为 test.cc 然后我们通过如下命令进行编译并调试 Clang : 

```
clang -cc1 -S -emit-llvm test.cc
```

然后我们进入调试模式。

首先进入的是位于 driver.cpp 中的 main 函数:

```
int main(int argc_, const char **argv_) {
  llvm::sys::PrintStackTraceOnErrorSignal();
  llvm::PrettyStackTraceProgram X(argc_, argv_);
```

然后进一步跟踪，看到下面部分代码：

```
  // Handle -cc1 integrated tools, even if -cc1 was expanded from a response
  // file.
  auto FirstArg = std::find_if(argv.begin() + 1, argv.end(),
                               [](const char *A) { return A != nullptr; });
  if (FirstArg != argv.end() && StringRef(*FirstArg).startswith("-cc1")) {
    // If -cc1 came from a response file, remove the EOL sentinels.
    if (MarkEOLs) {
      auto newEnd = std::remove(argv.begin(), argv.end(), nullptr);
      argv.resize(newEnd - argv.begin());
    }
    return ExecuteCC1Tool(argv, argv[1] + 4);
  }
```

这里通过判断第一个 argument 是否为以 `-cc1` 为前缀，是则调用 `ExecuteCC1Tool`，而我们命令中第一个参数正好为 `-cc1`，然后跟进 `ExecuteCC1Tool` 会进入到 `cc1_main`：

```
int cc1_main(ArrayRef<const char *> Argv, const char *Argv0, void *MainAddr) {
  std::unique_ptr<CompilerInstance> Clang(new CompilerInstance());
  IntrusiveRefCntPtr<DiagnosticIDs> DiagID(new DiagnosticIDs());
```

这个函数第一行代码便生成了一个 `CompilerInstance` 对象 `Clang`，继续跟进会发现下面代码：

```
  bool Success = CompilerInvocation::CreateFromArgs(
      Clang->getInvocation(), Argv.begin(), Argv.end(), Diags);
```

这里是根据 argument 为 `CompilerInstance` 创建一个 `CompilerInvocation` 实例，想来处理 argument 的代码就在里面。所以进入 `CreateFromArgs`：

```
  Success &= ParseAnalyzerArgs(*Res.getAnalyzerOpts(), Args, Diags);
  Success &= ParseMigratorArgs(Res.getMigratorOpts(), Args);
  ParseDependencyOutputArgs(Res.getDependencyOutputOpts(), Args);
  Success &= ParseDiagnosticArgs(Res.getDiagnosticOpts(), Args, &Diags);
  ParseCommentArgs(LangOpts.CommentOpts, Args);
  ParseFileSystemArgs(Res.getFileSystemOpts(), Args);
  // FIXME: We shouldn't have to pass the DashX option around here
  InputKind DashX = ParseFrontendArgs(Res.getFrontendOpts(), Args, Diags);
  ParseTargetArgs(Res.getTargetOpts(), Args, Diags);
  Success &= ParseCodeGenArgs(Res.getCodeGenOpts(), Args, DashX, Diags,
                              Res.getTargetOpts());
  ParseHeaderSearchArgs(Res.getHeaderSearchOpts(), Args);
  if (DashX == IK_AST || DashX == IK_LLVM_IR) {
    // ObjCAAutoRefCount and Sanitize LangOpts are used to setup the
    // PassManager in BackendUtil.cpp. They need to be initializd no matter
    // what the input type is.
    if (Args.hasArg(OPT_fobjc_arc))
      LangOpts.ObjCAutoRefCount = 1;
    // PIClevel and PIELevel are needed during code generation and this should be
    // set regardless of the input type.
    LangOpts.PICLevel = getLastArgIntValue(Args, OPT_pic_level, 0, Diags);
    LangOpts.PIELevel = getLastArgIntValue(Args, OPT_pie_level, 0, Diags);
    parseSanitizerKinds("-fsanitize=", Args.getAllArgValues(OPT_fsanitize_EQ),
                        Diags, LangOpts.Sanitize);
  } else {
    // Other LangOpts are only initialzed when the input is not AST or LLVM IR.
    ParseLangArgs(LangOpts, Args, DashX, Res.getTargetOpts(), Diags);
    if (Res.getFrontendOpts().ProgramAction == frontend::RewriteObjC)
      LangOpts.ObjCExceptions = 1;
  }
```

通过名称就可以猜出每行代码做了些什么功能，所以这里就不一一跟进，只看一下 `ParseFrontendArgs`：

```
static InputKind ParseFrontendArgs(FrontendOptions &Opts, ArgList &Args,
                                   DiagnosticsEngine &Diags) {
  using namespace options;
  Opts.ProgramAction = frontend::ParseSyntaxOnly;
  if (const Arg *A = Args.getLastArg(OPT_Action_Group)) {
    switch (A->getOption().getID()) {
    default:
      llvm_unreachable("Invalid option in group!");
    case OPT_ast_list:
      Opts.ProgramAction = frontend::ASTDeclList; break;
    case OPT_ast_dump:
    case OPT_ast_dump_lookups:
      Opts.ProgramAction = frontend::ASTDump; break;
    case OPT_ast_print:
      Opts.ProgramAction = frontend::ASTPrint; break;
    case OPT_ast_view:
      Opts.ProgramAction = frontend::ASTView; break;
    case OPT_dump_raw_tokens:
      Opts.ProgramAction = frontend::DumpRawTokens; break;
    case OPT_dump_tokens:
      Opts.ProgramAction = frontend::DumpTokens; break;
    case OPT_S:
      Opts.ProgramAction = frontend::EmitAssembly; break;
    case OPT_emit_llvm_bc:
      Opts.ProgramAction = frontend::EmitBC; break;
    case OPT_emit_html:
      Opts.ProgramAction = frontend::EmitHTML; break;
    case OPT_emit_llvm:
      Opts.ProgramAction = frontend::EmitLLVM; break;
    case OPT_emit_llvm_only:
      Opts.ProgramAction = frontend::EmitLLVMOnly; break;
    case OPT_emit_codegen_only:
      Opts.ProgramAction = frontend::EmitCodeGenOnly; break;
    case OPT_emit_obj:
      Opts.ProgramAction = frontend::EmitObj; break;
    case OPT_fixit_EQ:
      Opts.FixItSuffix = A->getValue();
      // fall-through!
    case OPT_fixit:
      Opts.ProgramAction = frontend::FixIt; break;
    case OPT_emit_module:
      Opts.ProgramAction = frontend::GenerateModule; break;
    case OPT_emit_pch:
      Opts.ProgramAction = frontend::GeneratePCH; break;
    case OPT_emit_pth:
      Opts.ProgramAction = frontend::GeneratePTH; break;
    case OPT_init_only:
      Opts.ProgramAction = frontend::InitOnly; break;
    case OPT_fsyntax_only:
      Opts.ProgramAction = frontend::ParseSyntaxOnly; break;
    case OPT_module_file_info:
      Opts.ProgramAction = frontend::ModuleFileInfo; break;
    case OPT_verify_pch:
      Opts.ProgramAction = frontend::VerifyPCH; break;
    case OPT_print_decl_contexts:
      Opts.ProgramAction = frontend::PrintDeclContext; break;
    case OPT_print_preamble:
      Opts.ProgramAction = frontend::PrintPreamble; break;
    case OPT_E:
      Opts.ProgramAction = frontend::PrintPreprocessedInput; break;
    case OPT_rewrite_macros:
      Opts.ProgramAction = frontend::RewriteMacros; break;
    case OPT_rewrite_objc:
      Opts.ProgramAction = frontend::RewriteObjC; break;
    case OPT_rewrite_test:
      Opts.ProgramAction = frontend::RewriteTest; break;
    case OPT_analyze:
      Opts.ProgramAction = frontend::RunAnalysis; break;
    case OPT_migrate:
      Opts.ProgramAction = frontend::MigrateSource; break;
    case OPT_Eonly:
      Opts.ProgramAction = frontend::RunPreprocessorOnly; break;
    }
  }
```

这里便是指定 Action 的地方，我们使用的 `-emit-llvm` ，则 `ProgramAction` 表示 `frontend::EmitLLVM`。

现在回到 `cc1_main`，紧急着便是执行 `frontend actions`：

```
  // Execute the frontend actions.
  Success = ExecuteCompilerInvocation(Clang.get());
```

目前为止，初始化编译器部分工作已经完成，下面就是执行部分。跟进 `ExecuteCompilerInvocation`，注意到下面一段代码：

```
  // Create and execute the frontend action.
  std::unique_ptr<FrontendAction> Act(CreateFrontendAction(*Clang));
  if (!Act)
    return false;
  bool Success = Clang->ExecuteAction(*Act);
```

这里就是根据 `ParseFrontendArgs` 中得到的 `ProgramAction` 来生成对应的 `Act`。紧接着，通过该  `Act` 调用 `ExecuteAction` 正式开始工作。

`CreateFrontendAction` 通过进一步调用 `CreateFrontendBaseAction` 来生成 `Act`，`CreateFrontendBaseAction` 中对应部分代码为：

```
switch (CI.getFrontendOpts().ProgramAction) {
  case ASTDeclList:            return llvm::make_unique<ASTDeclListAction>();
  case ASTDump:                return llvm::make_unique<ASTDumpAction>();
  case ASTPrint:               return llvm::make_unique<ASTPrintAction>();
  case ASTView:                return llvm::make_unique<ASTViewAction>();
  case DumpRawTokens:          return llvm::make_unique<DumpRawTokensAction>();
  case DumpTokens:             return llvm::make_unique<DumpTokensAction>();
  case EmitAssembly:           return llvm::make_unique<EmitAssemblyAction>();
  case EmitBC:                 return llvm::make_unique<EmitBCAction>();
  case EmitHTML:               return llvm::make_unique<HTMLPrintAction>();
  case EmitLLVM:               return llvm::make_unique<EmitLLVMAction>();
  case EmitLLVMOnly:           return llvm::make_unique<EmitLLVMOnlyAction>();
  case EmitCodeGenOnly:        return llvm::make_unique<EmitCodeGenOnlyAction>();
  case EmitObj:                return llvm::make_unique<EmitObjAction>();
  case FixIt:                  return llvm::make_unique<FixItAction>();
  case GenerateModule:         return llvm::make_unique<GenerateModuleAction>();
  case GeneratePCH:            return llvm::make_unique<GeneratePCHAction>();
  case GeneratePTH:            return llvm::make_unique<GeneratePTHAction>();
  case InitOnly:               return llvm::make_unique<InitOnlyAction>();
  case ParseSyntaxOnly:        return llvm::make_unique<SyntaxOnlyAction>();
  case ModuleFileInfo:         return llvm::make_unique<DumpModuleInfoAction>();
  case VerifyPCH:              return llvm::make_unique<VerifyPCHAction>();
```

在这里，就可以找到所有的 `Action` 方便后面使用。

`ExecuteAction` 中通过对每一个文件执行一次 `Execute` 来进行编译：

```
  for (const FrontendInputFile &FIF : getFrontendOpts().Inputs) {
    // Reset the ID tables if we are reusing the SourceManager and parsing
    // regular files.
    if (hasSourceManager() && !Act.isModelParsingAction())
      getSourceManager().clearIDTables();

    if (Act.BeginSourceFile(*this, FIF)) {
      Act.Execute();
      Act.EndSourceFile();
    }
  }
```

`Execute` 中，通过进一步调用所对应实例的 `ExecuteAction` 来具体执行，所以这里紧接着关心的便是每个 `Action` 对应的 `ExecuteAction` 部分。到此为止，工作流程部分告一段落，接下来具体分析的是对应的 `Action`。 