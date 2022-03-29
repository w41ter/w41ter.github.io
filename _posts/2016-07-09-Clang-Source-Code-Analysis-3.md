---
layout: post
title: Clang Source Code Analysis (3)
date: 2016-07-09 13:29:02
tags: Compile
categories: Clang 源码分析
---

在 `ParseAST` 中，前面通过 `P.ParseTopLevelDecl(ADecl)` 对源代码进行了分析，紧接着就是调用 `HandleTopLevelDecl(ADecl.get())` 进行处理。

<!-- more -->

代码生成的部分由 `HandleTopLevelDecl` 负责，而 `ASTConsumer` 是一个虚基类，所以需要从其他地方入手。这里以 `ASTConsumer` 为切入点，找到创建位置。

假设我们使用的是 --emit-llvm 模式，而 `EmitLLVMAction` 继承自 `CodeGenAction`。在 `CodeGenAction` 中找到创建 `ASTConsumer` 的 `CreateASTConsumer`。

```
std::unique_ptr<ASTConsumer>
CodeGenAction::CreateASTConsumer(CompilerInstance &CI, StringRef InFile) {
  // ...
  std::unique_ptr<BackendConsumer> Result(new BackendConsumer(
      BA, CI.getDiagnostics(), CI.getHeaderSearchOpts(),
      CI.getPreprocessorOpts(), CI.getCodeGenOpts(), CI.getTargetOpts(),
      CI.getLangOpts(), CI.getFrontendOpts().ShowTimers, InFile, LinkModules,
      OS, *VMContext, CoverageInfo));
  BEConsumer = Result.get();
  return std::move(Result);
}
```

实际上是一个 `BackendConsumer` 实例。另外观察 `CodeGenAction::ExecuteAction` :

```
void CodeGenAction::ExecuteAction() {
  // If this is an IR file, we have to treat it specially.
  if (getCurrentFileKind() == IK_LLVM_IR) {
    // ...
  }

  // Otherwise follow the normal AST path.
  this->ASTFrontendAction::ExecuteAction();
}
```

发现其实际上是执行的 `ASTFrontendAction::ExecuteAction`，所以原来分析的部分仍然可以使用。现在，找到 `BackendConsumer::HandleTopLevelDecl`：

```
bool HandleTopLevelDecl(DeclGroupRef D) override {
    Gen->HandleTopLevelDecl(D);
    return true;
}
```

这里进一步调用 `CodeGenerator::HandleTopLevelDecl`，而 `Gen` 由 `CreateLLVMCodeGen` 得到：

```
CodeGenerator *clang::CreateLLVMCodeGen(
    DiagnosticsEngine &Diags, const std::string &ModuleName,
    const HeaderSearchOptions &HeaderSearchOpts,
    const PreprocessorOptions &PreprocessorOpts, const CodeGenOptions &CGO,
    llvm::LLVMContext &C, CoverageSourceInfo *CoverageInfo) {
  return new CodeGeneratorImpl(Diags, ModuleName, HeaderSearchOpts,
                               PreprocessorOpts, CGO, C, CoverageInfo);
}
```

所以，`Gen` 实际上是一个 `CodeGeneratorImpl` 实例。

```
bool HandleTopLevelDecl(DeclGroupRef DG) override {
    if (Diags.hasErrorOccurred())
    return true;

    HandlingTopLevelDeclRAII HandlingDecl(*this);

    // Make sure to emit all elements of a Decl.
    for (DeclGroupRef::iterator I = DG.begin(), E = DG.end(); I != E; ++I)
        Builder->EmitTopLevelDecl(*I);

    return true;
}
```

上面是 `CodeGeneratorImpl::HandleTopLevelDecl` 部分，这里对每个声明部分调用 `EmitTopLevelDecl` 处理。`Builder` 是 `CodeGenModule` 类对象。

```
void CodeGenModule::EmitTopLevelDecl(Decl *D) {
  // Ignore dependent declarations.
  if (D->getDeclContext() && D->getDeclContext()->isDependentContext())
    return;

  switch (D->getKind()) {
  case Decl::CXXConversion:
  case Decl::CXXMethod:
  case Decl::Function:
    // Skip function templates
    if (cast<FunctionDecl>(D)->getDescribedFunctionTemplate() ||
        cast<FunctionDecl>(D)->isLateTemplateParsed())
      return;

    EmitGlobal(cast<FunctionDecl>(D));
    // Always provide some coverage mapping
    // even for the functions that aren't emitted.
    AddDeferredUnusedCoverageMapping(D);
    break;

  case Decl::Var:
    // Skip variable templates
    if (cast<VarDecl>(D)->getDescribedVarTemplate())
      return;
  case Decl::VarTemplateSpecialization:
    EmitGlobal(cast<VarDecl>(D));
    break;

  // Indirect fields from global anonymous structs and unions can be
  // ignored; only the actual variable requires IR gen support.
  case Decl::IndirectField:
    break;
  }
}
```

在 `CodeGenModule::EmitTopLevelDecl` 中，可以发现对函数和变量等而言，调用的其实是 `EmitGlobal`。跟进 `EmitGlobal`，发现最终的调用实际上是 `EmitGlobalDefinition`。

```
void CodeGenModule::EmitGlobalDefinition(GlobalDecl GD, llvm::GlobalValue *GV) {
  const auto *D = cast<ValueDecl>(GD.getDecl());

  if (isa<FunctionDecl>(D)) {
    return EmitGlobalFunctionDefinition(GD, GV);
  }

  if (const auto *VD = dyn_cast<VarDecl>(D))
    return EmitGlobalVarDefinition(VD, !VD->hasDefinition());
  
  llvm_unreachable("Invalid argument to EmitGlobalDefinition()");
}
```

可以发现最终的调用分别为 `EmitGlobalFunctionDefinition` 和 `EmitGlobalVarDefinition`。这两个函数调用很明显，一个是函数定义，一个是变量定义。

```
void CodeGenModule::EmitGlobalFunctionDefinition(GlobalDecl GD,
                                                 llvm::GlobalValue *GV) {
  const auto *D = cast<FunctionDecl>(GD.getDecl());

  // Compute the function info and LLVM type.
  const CGFunctionInfo &FI = getTypes().arrangeGlobalDeclaration(GD);
  llvm::FunctionType *Ty = getTypes().GetFunctionType(FI);

  // Get or create the prototype for the function.
  if (!GV || (GV->getType()->getElementType() != Ty))
    GV = cast<llvm::GlobalValue>(GetAddrOfFunction(GD, Ty, /*ForVTable=*/false,
                                                   /*DontDefer=*/true,
                                                   /*IsForDefinition=*/true));

  // Already emitted.
  if (!GV->isDeclaration())
    return;

  // We need to set linkage and visibility on the function before
  // generating code for it because various parts of IR generation
  // want to propagate this information down (e.g. to local static
  // declarations).
  auto *Fn = cast<llvm::Function>(GV);
  setFunctionLinkage(GD, Fn);
  setFunctionDLLStorageClass(GD, Fn);

  // FIXME: this is redundant with part of setFunctionDefinitionAttributes
  setGlobalVisibility(Fn, D);
  // ...
  CodeGenFunction(*this).GenerateCode(D, Fn, FI);
  // ...
}
```

这里先产生函数签名，最后调用 `CodeGenFunction::GenerateCode` 生成代码。

具体的内容就不继续分析下去了，到这里为止，已经梳理了一边 Clang 执行流程，整理出一个具体框架。还有很多深入的等待继续挖掘。