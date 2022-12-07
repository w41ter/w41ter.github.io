---
layout: post
title: Rust - The `async fn` generated `Future` is too large?
---

# 背景

最近开始对 engula 进行性能测试，发现 async fn 的性能损耗非常大，这不符合 zero overhead abstraction，因此开始对 async fn 的性能做一些研究。

通过增加参数 `-Z print-type-size`，可以输出每种类型的大小。发现很多 generator 内存大小非常大，其中最不符合直觉的是下面这几个：

```log
print-type-size type: `std::future::from_generator::GenFuture<[static generator@src/client/src/node_client.rs:39:69: 44:6]>`: 1248 bytes, alignment: 8 bytes
print-type-size     field `.0`: 1248 bytes
print-type-size type: `std::future::from_generator::GenFuture<[static generator@src/client/src/node_client.rs:79:52: 83:6]>`: 1408 bytes, alignment: 8 bytes
print-type-size     field `.0`: 1408 bytes
print-type-size type: `std::future::from_generator::GenFuture<[static generator@src/client/src/node_client.rs:88:51: 92:6]>`: 1408 bytes, alignment: 8 bytes
print-type-size     field `.0`: 1408 bytes
```

node_client.rs 是 tonic grpc client 的简单封装:

```rust
use tonic::transport::Channel;

#[derive(Debug, Clone)]
pub struct Client {
    client: node_client::NodeClient<Channel>,
}

pub async fn root_heartbeat(
    &self,
    req: HeartbeatRequest,
) -> Result<HeartbeatResponse, tonic::Status> {
    let mut client = self.client.clone();
    let res = client.root_heartbeat(req).await?;
    Ok(res.into_inner())
}
```

`node_client::NodeClient` 是 tonic_build 生成的代码：

```rust
impl<T> NodeClient<T>
where
    T: tonic::client::GrpcService<tonic::body::BoxBody>,
    T::Error: Into<StdError>,
    T::ResponseBody: Body<Data = Bytes> + Send + 'static,
    <T::ResponseBody as Body>::Error: Into<StdError> + Send,
{
    pub fn new(inner: T) -> Self {
        let inner = tonic::client::Grpc::new(inner);
        Self { inner }
    }    
}

pub async fn root_heartbeat(
    &mut self,
    request: impl tonic::IntoRequest<super::HeartbeatRequest>,
) -> Result<tonic::Response<super::HeartbeatResponse>, tonic::Status> {
    self.inner
        .ready()
        .await
        .map_err(|e| {
            tonic::Status::new(
                tonic::Code::Unknown,
                format!("Service was not ready: {}", e.into()),
            )
        })?;
    let codec = tonic::codec::ProstCodec::default();
    let path = http::uri::PathAndQuery::from_static(
        "/engula.server.v1.Node/RootHeartbeat",
    );
    self.inner.unary(request.into_request(), path, codec).await
}
```

也就是说，每次调用 `Grpc::unary` 需要在栈上开辟 1K+ 的空间。如果最后使用了 `tokio::spawn`，那么还需要将它复制到堆上。无论是内存分配还是复制上的开销，对于一个高性能存储服务都是不可接受的。并且随着 `async fn` 的调用层数增加，`Future` 大小还会呈现指数增长，这一点我后面会分析。

# Grpc::unary 的 memory layout 是怎样的？

那么，为何 `Grpc::unary` 返回的 `Future` 需要消耗 1K+ 的内存空间呢？

在 tonic/src/client/grpc.rs 中，`unary` 最终被委托给 `Grpc::streaming`，后者调用 `Channel::call` 并返回 `ResponseFuture`。

```Rust
/// Send a single unary gRPC request.
pub async fn unary<M1, M2, C>(
    &mut self,
    request: Request<M1>,
    path: PathAndQuery,
    codec: C,
) -> Result<Response<M2>, Status>
where
    T: GrpcService<BoxBody>,
    T::ResponseBody: Body + Send + 'static,
    <T::ResponseBody as Body>::Error: Into<crate::Error>,
    C: Codec<Encode = M1, Decode = M2>,
    M1: Send + Sync + 'static,
    M2: Send + Sync + 'static,
{
    let request = request.map(|m| stream::once(future::ready(m)));
    self.client_streaming(request, path, codec).await
}

/// Send a client side streaming gRPC request.
pub async fn client_streaming<S, M1, M2, C>(
    &mut self,
    request: Request<S>,
    path: PathAndQuery,
    codec: C,
) -> Result<Response<M2>, Status>
where
    T: GrpcService<BoxBody>,
    T::ResponseBody: Body + Send + 'static,
    <T::ResponseBody as Body>::Error: Into<crate::Error>,
    S: Stream<Item = M1> + Send + 'static,
    C: Codec<Encode = M1, Decode = M2>,
    M1: Send + Sync + 'static,
    M2: Send + Sync + 'static,
{
    let (mut parts, body, extensions) =
        self.streaming(request, path, codec).await?.into_parts();

    futures_util::pin_mut!(body);

    let message = body
        .try_next()
        .await
        .map_err(|mut status| {
            status.metadata_mut().merge(parts.clone());
            status
        })?
        .ok_or_else(|| Status::new(Code::Internal, "Missing response message."))?;

    if let Some(trailers) = body.trailers().await? {
        parts.merge(trailers);
    }

    Ok(Response::from_parts(parts, message, extensions))
}

/// Send a bi-directional streaming gRPC request.
pub async fn streaming<S, M1, M2, C>(
    &mut self,
    request: Request<S>,
    path: PathAndQuery,
    mut codec: C,
) -> Result<Response<Streaming<M2>>, Status>
where
    T: GrpcService<BoxBody>,
    T::ResponseBody: Body + Send + 'static,
    <T::ResponseBody as Body>::Error: Into<crate::Error>,
    S: Stream<Item = M1> + Send + 'static,
    C: Codec<Encode = M1, Decode = M2>,
    M1: Send + Sync + 'static,
    M2: Send + Sync + 'static,
{
    let mut parts = Parts::default();
    parts.path_and_query = Some(path);

    let uri = Uri::from_parts(parts).expect("path_and_query only is valid Uri");

    let request = request
        .map(|s| {
            encode_client(
                codec.encoder(),
                s,
                #[cfg(feature = "compression")]
                self.send_compression_encodings,
            )
        })
        .map(BoxBody::new);

    let mut request = request.into_http(
        uri,
        http::Method::POST,
        http::Version::HTTP_2,
        SanitizeHeaders::Yes,
    );

    // Add the gRPC related HTTP headers
    request
        .headers_mut()
        .insert(TE, HeaderValue::from_static("trailers"));

    // Set the content type
    request
        .headers_mut()
        .insert(CONTENT_TYPE, HeaderValue::from_static("application/grpc"));

    #[cfg(feature = "compression")]
    {
        if let Some(encoding) = self.send_compression_encodings {
            request.headers_mut().insert(
                crate::codec::compression::ENCODING_HEADER,
                encoding.into_header_value(),
            );
        }

        if let Some(header_value) = self
            .accept_compression_encodings
            .into_accept_encoding_header_value()
        {
            request.headers_mut().insert(
                crate::codec::compression::ACCEPT_ENCODING_HEADER,
                header_value,
            );
        }
    }

    let response = self
        .inner
        .call(request)
        .await
        .map_err(|err| Status::from_error(err.into()))?;

    #[cfg(feature = "compression")]
    let encoding = CompressionEncoding::from_encoding_header(
        response.headers(),
        self.accept_compression_encodings,
    )?;

    let status_code = response.status();
    let trailers_only_status = Status::from_header_map(response.headers());

    // We do not need to check for trailers if the `grpc-status` header is present
    // with a valid code.
    let expect_additional_trailers = if let Some(status) = trailers_only_status {
        if status.code() != Code::Ok {
            return Err(status);
        }

        false
    } else {
        true
    };

    let response = response.map(|body| {
        if expect_additional_trailers {
            Streaming::new_response(
                codec.decoder(),
                body,
                status_code,
                #[cfg(feature = "compression")]
                encoding,
            )
        } else {
            Streaming::new_empty(codec.decoder(), body)
        }
    });

    Ok(Response::from_http(response))
}
```

以前面的 `root_heartbeat` 为例，最终实例化的 `streaming` 的签名为：

```
tonic::client::Grpc<tonic::transport::Channel>::streaming<
    futures::stream::Once<
        futures::future::Ready<
            engula_api::server::v1::HeartbeatRequest>>,
    engula_api::server::v1::HeartbeatRequest,
    engula_api::server::v1::HeartbeatResponse,
    tonic::codec::ProstCodec<
        engula_api::server::v1::HeartbeatRequest,
        engula_api::server::v1::HeartbeatResponse>>
```

而 `async fn streaming()` 脱糖后，经过 transform 生成的状态机的内存布局为：

```
generator layout ([static generator@tonic::client::Grpc<tonic::transport::Channel>::streaming<futures::stream::Once<futures::future::Ready<engula_api::server::v1::HeartbeatRequest>>, engula_api::server::v1::HeartbeatRequest, engula_api::server::v1::HeartbeatResponse, tonic::codec::ProstCodec<engula_api::server::v1::HeartbeatRequest, engula_api::server::v1::HeartbeatResponse>>::{closure#0}]): Layout {
    size: Size(560 bytes),
    align: AbiAndPrefAlign {
        abi: Align(8 bytes),
        pref: Align(8 bytes),
    },
    abi: Aggregate {
        sized: true,
    },
    fields: Arbitrary {
        offsets: [
        Size(0 bytes),
        Size(8 bytes),
        Size(152 bytes),
        Size(0 bytes),
        Size(552 bytes),
        ],
    }
}
```

仔细分析 `streaming` 的代码可以发现，跨过 `suspend point` 的变量只有本地变量 `request`，预留空间 `response`:

- `request`: `http::request::Request<http_body::combinators::box_body::UnsyncBoxBody<prost::bytes::Bytes, tonic::Status>>` size = 240 bytes
- `response`: `tonic::transport::channel::ResponseFuture` size = 32 bytes

那么 `request` + `response` + `tag` （手写状态机的理论值）应该是远小于 560 bytes。到了 `client_streaming` 这里，内存空间就增长到了 1056 bytes。

# async fn 的 layout 是如何计算的？

这里进一步分析编译器内部是如何处理 `async`, `await` 和产生状态机的，看看不符合直觉的结果是如何产生的。

## 实际上 async fn 是 generator 的语法糖

`async` 和 `await` 都是语法糖，rust compiler 在 ast lowering 过程中进行了 desugar，并生成 hir。其中 `async fn` 会被替换为 generator (compiler/rustc_ast_lowering/src/item.rs)：

```rust
fn lower_maybe_async_body(
    &mut self,
    span: Span,
    decl: &FnDecl,
    asyncness: Async,
    body: Option<&Block>,
) -> hir::BodyId {
    let closure_id = match asyncness {
        Async::Yes { closure_id, .. } => closure_id,
        Async::No => return self.lower_fn_body_block(span, decl, body),
    };

    self.lower_body(|this| {
        let mut parameters: Vec<hir::Param<'_>> = Vec::new();
        let mut statements: Vec<hir::Stmt<'_>> = Vec::new();

        // Async function parameters are lowered into the closure body so that they are
        // captured and so that the drop order matches the equivalent non-async functions.
        //
        // from:
        //
        //     async fn foo(<pattern>: <ty>, <pattern>: <ty>, <pattern>: <ty>) {
        //         <body>
        //     }
        //
        // into:
        //
        //     fn foo(__arg0: <ty>, __arg1: <ty>, __arg2: <ty>) {
        //       async move {
        //         let __arg2 = __arg2;
        //         let <pattern> = __arg2;
        //         let __arg1 = __arg1;
        //         let <pattern> = __arg1;
        //         let __arg0 = __arg0;
        //         let <pattern> = __arg0;
        //         drop-temps { <body> } // see comments later in fn for details
        //       }
        //     }
        //
        // If `<pattern>` is a simple ident, then it is lowered to a single
        // `let <pattern> = <pattern>;` statement as an optimization.
        //
        // Note that the body is embedded in `drop-temps`; an
        // equivalent desugaring would be `return { <body>
        // };`. The key point is that we wish to drop all the
        // let-bound variables and temporaries created in the body
        // (and its tail expression!) before we drop the
        // parameters (c.f. rust-lang/rust#64512).
        for (index, parameter) in decl.inputs.iter().enumerate() {
            let parameter = this.lower_param(parameter);
            let span = parameter.pat.span;

            // Check if this is a binding pattern, if so, we can optimize and avoid adding a
            // `let <pat> = __argN;` statement. In this case, we do not rename the parameter.
            let (ident, is_simple_parameter) = match parameter.pat.kind {
                hir::PatKind::Binding(
                    hir::BindingAnnotation::Unannotated | hir::BindingAnnotation::Mutable,
                    _,
                    ident,
                    _,
                ) => (ident, true),
                // For `ref mut` or wildcard arguments, we can't reuse the binding, but
                // we can keep the same name for the parameter.
                // This lets rustdoc render it correctly in documentation.
                hir::PatKind::Binding(_, _, ident, _) => (ident, false),
                hir::PatKind::Wild => {
                    (Ident::with_dummy_span(rustc_span::symbol::kw::Underscore), false)
                }
                _ => {
                    // Replace the ident for bindings that aren't simple.
                    let name = format!("__arg{}", index);
                    let ident = Ident::from_str(&name);

                    (ident, false)
                }
            };

            let desugared_span = this.mark_span_with_reason(DesugaringKind::Async, span, None);

            // Construct a parameter representing `__argN: <ty>` to replace the parameter of the
            // async function.
            //
            // If this is the simple case, this parameter will end up being the same as the
            // original parameter, but with a different pattern id.
            let stmt_attrs = this.attrs.get(&parameter.hir_id.local_id).copied();
            let (new_parameter_pat, new_parameter_id) = this.pat_ident(desugared_span, ident);
            let new_parameter = hir::Param {
                hir_id: parameter.hir_id,
                pat: new_parameter_pat,
                ty_span: this.lower_span(parameter.ty_span),
                span: this.lower_span(parameter.span),
            };

            if is_simple_parameter {
                // If this is the simple case, then we only insert one statement that is
                // `let <pat> = <pat>;`. We re-use the original argument's pattern so that
                // `HirId`s are densely assigned.
                let expr = this.expr_ident(desugared_span, ident, new_parameter_id);
                let stmt = this.stmt_let_pat(
                    stmt_attrs,
                    desugared_span,
                    Some(expr),
                    parameter.pat,
                    hir::LocalSource::AsyncFn,
                );
                statements.push(stmt);
            } else {
                // If this is not the simple case, then we construct two statements:
                //
                // ```
                // let __argN = __argN;
                // let <pat> = __argN;
                // ```
                //
                // The first statement moves the parameter into the closure and thus ensures
                // that the drop order is correct.
                //
                // The second statement creates the bindings that the user wrote.

                // Construct the `let mut __argN = __argN;` statement. It must be a mut binding
                // because the user may have specified a `ref mut` binding in the next
                // statement.
                let (move_pat, move_id) = this.pat_ident_binding_mode(
                    desugared_span,
                    ident,
                    hir::BindingAnnotation::Mutable,
                );
                let move_expr = this.expr_ident(desugared_span, ident, new_parameter_id);
                let move_stmt = this.stmt_let_pat(
                    None,
                    desugared_span,
                    Some(move_expr),
                    move_pat,
                    hir::LocalSource::AsyncFn,
                );

                // Construct the `let <pat> = __argN;` statement. We re-use the original
                // parameter's pattern so that `HirId`s are densely assigned.
                let pattern_expr = this.expr_ident(desugared_span, ident, move_id);
                let pattern_stmt = this.stmt_let_pat(
                    stmt_attrs,
                    desugared_span,
                    Some(pattern_expr),
                    parameter.pat,
                    hir::LocalSource::AsyncFn,
                );

                statements.push(move_stmt);
                statements.push(pattern_stmt);
            };

            parameters.push(new_parameter);
        }

        let body_span = body.map_or(span, |b| b.span);
        let async_expr = this.make_async_expr(
            CaptureBy::Value,
            closure_id,
            None,
            body_span,
            hir::AsyncGeneratorKind::Fn,
            |this| {
                // Create a block from the user's function body:
                let user_body = this.lower_block_expr_opt(body_span, body);

                // Transform into `drop-temps { <user-body> }`, an expression:
                let desugared_span =
                    this.mark_span_with_reason(DesugaringKind::Async, user_body.span, None);
                let user_body = this.expr_drop_temps(
                    desugared_span,
                    this.arena.alloc(user_body),
                    AttrVec::new(),
                );

                // As noted above, create the final block like
                //
                // ```
                // {
                //   let $param_pattern = $raw_param;
                //   ...
                //   drop-temps { <user-body> }
                // }
                // ```
                let body = this.block_all(
                    desugared_span,
                    this.arena.alloc_from_iter(statements),
                    Some(user_body),
                );

                this.expr_block(body, AttrVec::new())
            },
        );

        (
            this.arena.alloc_from_iter(parameters),
            this.expr(body_span, async_expr, AttrVec::new()),
        )
    })
}
```

`async fn` 被替换为 generator 后，它的参数作为 captured variable 保存在 closure 中，后续称它为 upvars，在计算 `Layout` 是会使用到。

`await` 则会被替换为 `poll()`(compiler/rustc_ast_lowering/src/expr.rs):

```rust
/// Desugar `<expr>.await` into:
/// ```ignore (pseudo-rust)
/// match ::std::future::IntoFuture::into_future(<expr>) {
///     mut __awaitee => loop {
///         match unsafe { ::std::future::Future::poll(
///             <::std::pin::Pin>::new_unchecked(&mut __awaitee),
///             ::std::future::get_context(task_context),
///         ) } {
///             ::std::task::Poll::Ready(result) => break result,
///             ::std::task::Poll::Pending => {}
///         }
///         task_context = yield ();
///     }
/// }
/// ```
fn lower_expr_await(&mut self, dot_await_span: Span, expr: &Expr) -> hir::ExprKind<'hir> {
    let full_span = expr.span.to(dot_await_span);
    match self.generator_kind {
        Some(hir::GeneratorKind::Async(_)) => {}
        Some(hir::GeneratorKind::Gen) | None => {
            self.tcx.sess.emit_err(AwaitOnlyInAsyncFnAndBlocks {
                dot_await_span,
                item_span: self.current_item,
            });
        }
    }
    let span = self.mark_span_with_reason(DesugaringKind::Await, dot_await_span, None);
    let gen_future_span = self.mark_span_with_reason(
        DesugaringKind::Await,
        full_span,
        self.allow_gen_future.clone(),
    );
    let expr = self.lower_expr_mut(expr);
    let expr_hir_id = expr.hir_id;

    // Note that the name of this binding must not be changed to something else because
    // debuggers and debugger extensions expect it to be called `__awaitee`. They use
    // this name to identify what is being awaited by a suspended async functions.
    let awaitee_ident = Ident::with_dummy_span(sym::__awaitee);
    let (awaitee_pat, awaitee_pat_hid) =
        self.pat_ident_binding_mode(span, awaitee_ident, hir::BindingAnnotation::Mutable);

    let task_context_ident = Ident::with_dummy_span(sym::_task_context);

    // unsafe {
    //     ::std::future::Future::poll(
    //         ::std::pin::Pin::new_unchecked(&mut __awaitee),
    //         ::std::future::get_context(task_context),
    //     )
    // }
    let poll_expr = {
        let awaitee = self.expr_ident(span, awaitee_ident, awaitee_pat_hid);
        let ref_mut_awaitee = self.expr_mut_addr_of(span, awaitee);
        let task_context = if let Some(task_context_hid) = self.task_context {
            self.expr_ident_mut(span, task_context_ident, task_context_hid)
        } else {
            // Use of `await` outside of an async context, we cannot use `task_context` here.
            self.expr_err(span)
        };
        let new_unchecked = self.expr_call_lang_item_fn_mut(
            span,
            hir::LangItem::PinNewUnchecked,
            arena_vec![self; ref_mut_awaitee],
            Some(expr_hir_id),
        );
        let get_context = self.expr_call_lang_item_fn_mut(
            gen_future_span,
            hir::LangItem::GetContext,
            arena_vec![self; task_context],
            Some(expr_hir_id),
        );
        let call = self.expr_call_lang_item_fn(
            span,
            hir::LangItem::FuturePoll,
            arena_vec![self; new_unchecked, get_context],
            Some(expr_hir_id),
        );
        self.arena.alloc(self.expr_unsafe(call))
    };

    // `::std::task::Poll::Ready(result) => break result`
    let loop_node_id = self.next_node_id();
    let loop_hir_id = self.lower_node_id(loop_node_id);
    let ready_arm = {
        let x_ident = Ident::with_dummy_span(sym::result);
        let (x_pat, x_pat_hid) = self.pat_ident(gen_future_span, x_ident);
        let x_expr = self.expr_ident(gen_future_span, x_ident, x_pat_hid);
        let ready_field = self.single_pat_field(gen_future_span, x_pat);
        let ready_pat = self.pat_lang_item_variant(
            span,
            hir::LangItem::PollReady,
            ready_field,
            Some(expr_hir_id),
        );
        let break_x = self.with_loop_scope(loop_node_id, move |this| {
            let expr_break =
                hir::ExprKind::Break(this.lower_loop_destination(None), Some(x_expr));
            this.arena.alloc(this.expr(gen_future_span, expr_break, AttrVec::new()))
        });
        self.arm(ready_pat, break_x)
    };

    // `::std::task::Poll::Pending => {}`
    let pending_arm = {
        let pending_pat = self.pat_lang_item_variant(
            span,
            hir::LangItem::PollPending,
            &[],
            Some(expr_hir_id),
        );
        let empty_block = self.expr_block_empty(span);
        self.arm(pending_pat, empty_block)
    };

    let inner_match_stmt = {
        let match_expr = self.expr_match(
            span,
            poll_expr,
            arena_vec![self; ready_arm, pending_arm],
            hir::MatchSource::AwaitDesugar,
        );
        self.stmt_expr(span, match_expr)
    };

    // task_context = yield ();
    let yield_stmt = {
        let unit = self.expr_unit(span);
        let yield_expr = self.expr(
            span,
            hir::ExprKind::Yield(unit, hir::YieldSource::Await { expr: Some(expr_hir_id) }),
            AttrVec::new(),
        );
        let yield_expr = self.arena.alloc(yield_expr);

        if let Some(task_context_hid) = self.task_context {
            let lhs = self.expr_ident(span, task_context_ident, task_context_hid);
            let assign = self.expr(
                span,
                hir::ExprKind::Assign(lhs, yield_expr, self.lower_span(span)),
                AttrVec::new(),
            );
            self.stmt_expr(span, assign)
        } else {
            // Use of `await` outside of an async context. Return `yield_expr` so that we can
            // proceed with type checking.
            self.stmt(span, hir::StmtKind::Semi(yield_expr))
        }
    };

    let loop_block = self.block_all(span, arena_vec![self; inner_match_stmt, yield_stmt], None);

    // loop { .. }
    let loop_expr = self.arena.alloc(hir::Expr {
        hir_id: loop_hir_id,
        kind: hir::ExprKind::Loop(
            loop_block,
            None,
            hir::LoopSource::Loop,
            self.lower_span(span),
        ),
        span: self.lower_span(span),
    });

    // mut __awaitee => loop { ... }
    let awaitee_arm = self.arm(awaitee_pat, loop_expr);

    // `match ::std::future::IntoFuture::into_future(<expr>) { ... }`
    let into_future_span = self.mark_span_with_reason(
        DesugaringKind::Await,
        dot_await_span,
        self.allow_into_future.clone(),
    );
    let into_future_expr = self.expr_call_lang_item_fn(
        into_future_span,
        hir::LangItem::IntoFutureIntoFuture,
        arena_vec![self; expr],
        Some(expr_hir_id),
    );

    // match <into_future_expr> {
    //     mut __awaitee => loop { .. }
    // }
    hir::ExprKind::Match(
        into_future_expr,
        arena_vec![self; awaitee_arm],
        hir::MatchSource::AwaitDesugar,
    )
}
```

## generator 会被替换为 GeneratorState

此后 hir 会转换为 mir，generator 在 mir_transform 中被替换为 `GeneratorState`(compiler/rustc_mir_transform/src/generator.rs):

```rust
impl<'tcx> MirPass<'tcx> for StateTransform {
    fn run_pass(&self, tcx: TyCtxt<'tcx>, body: &mut Body<'tcx>) {
        let Some(yield_ty) = body.yield_ty() else {
            // This only applies to generators
            return;
        };

        assert!(body.generator_drop().is_none());
        dump_mir(tcx, None, "generator_before", &0, body, |_, _| Ok(()));

        // The first argument is the generator type passed by value
        let gen_ty = body.local_decls.raw[1].ty;

        // Get the interior types and substs which typeck computed
        let (upvars, interior, discr_ty, movable) = match *gen_ty.kind() {
            ty::Generator(_, substs, movability) => {
                let substs = substs.as_generator();
                (
                    substs.upvar_tys().collect(),
                    substs.witness(),
                    substs.discr_ty(tcx),
                    movability == hir::Movability::Movable,
                )
            }
            _ => {
                tcx.sess
                    .delay_span_bug(body.span, &format!("unexpected generator type {}", gen_ty));
                return;
            }
        };

        // Compute GeneratorState<yield_ty, return_ty>
        let state_did = tcx.require_lang_item(LangItem::GeneratorState, None);
        let state_adt_ref = tcx.adt_def(state_did);
        let state_substs = tcx.intern_substs(&[yield_ty.into(), body.return_ty().into()]);
        let ret_ty = tcx.mk_adt(state_adt_ref, state_substs);

        // We rename RETURN_PLACE which has type mir.return_ty to new_ret_local
        // RETURN_PLACE then is a fresh unused local with type ret_ty.
        let new_ret_local = replace_local(RETURN_PLACE, ret_ty, body, tcx);

        // We also replace the resume argument and insert an `Assign`.
        // This is needed because the resume argument `_2` might be live across a `yield`, in which
        // case there is no `Assign` to it that the transform can turn into a store to the generator
        // state. After the yield the slot in the generator state would then be uninitialized.
        let resume_local = Local::new(2);
        let new_resume_local =
            replace_local(resume_local, body.local_decls[resume_local].ty, body, tcx);

        // When first entering the generator, move the resume argument into its new local.
        let source_info = SourceInfo::outermost(body.span);
        let stmts = &mut body.basic_blocks_mut()[BasicBlock::new(0)].statements;
        stmts.insert(
            0,
            Statement {
                source_info,
                kind: StatementKind::Assign(Box::new((
                    new_resume_local.into(),
                    Rvalue::Use(Operand::Move(resume_local.into())),
                ))),
            },
        );

        let always_live_locals = always_storage_live_locals(&body);

        let liveness_info =
            locals_live_across_suspend_points(tcx, body, &always_live_locals, movable);

        sanitize_witness(tcx, body, interior, upvars, &liveness_info.saved_locals);

        if tcx.sess.opts.unstable_opts.validate_mir {
            let mut vis = EnsureGeneratorFieldAssignmentsNeverAlias {
                assigned_local: None,
                saved_locals: &liveness_info.saved_locals,
                storage_conflicts: &liveness_info.storage_conflicts,
            };

            vis.visit_body(body);
        }

        // Extract locals which are live across suspension point into `layout`
        // `remap` gives a mapping from local indices onto generator struct indices
        // `storage_liveness` tells us which locals have live storage at suspension points
        let (remap, layout, storage_liveness) = compute_layout(liveness_info, body);

        let can_return = can_return(tcx, body, tcx.param_env(body.source.def_id()));

        // Run the transformation which converts Places from Local to generator struct
        // accesses for locals in `remap`.
        // It also rewrites `return x` and `yield y` as writing a new generator state and returning
        // GeneratorState::Complete(x) and GeneratorState::Yielded(y) respectively.
        let mut transform = TransformVisitor {
            tcx,
            state_adt_ref,
            state_substs,
            remap,
            storage_liveness,
            always_live_locals,
            suspension_points: Vec::new(),
            new_ret_local,
            discr_ty,
        };
        transform.visit_body(body);

        // Update our MIR struct to reflect the changes we've made
        body.arg_count = 2; // self, resume arg
        body.spread_arg = None;

        body.generator.as_mut().unwrap().yield_ty = None;
        body.generator.as_mut().unwrap().generator_layout = Some(layout);

        // Insert `drop(generator_struct)` which is used to drop upvars for generators in
        // the unresumed state.
        // This is expanded to a drop ladder in `elaborate_generator_drops`.
        let drop_clean = insert_clean_drop(body);

        dump_mir(tcx, None, "generator_pre-elab", &0, body, |_, _| Ok(()));

        // Expand `drop(generator_struct)` to a drop ladder which destroys upvars.
        // If any upvars are moved out of, drop elaboration will handle upvar destruction.
        // However we need to also elaborate the code generated by `insert_clean_drop`.
        elaborate_generator_drops(tcx, body);

        dump_mir(tcx, None, "generator_post-transform", &0, body, |_, _| Ok(()));

        // Create a copy of our MIR and use it to create the drop shim for the generator
        let drop_shim = create_generator_drop_shim(tcx, &transform, gen_ty, body, drop_clean);

        body.generator.as_mut().unwrap().generator_drop = Some(drop_shim);

        // Create the Generator::resume function
        create_generator_resume_function(tcx, transform, body, can_return);

        // Run derefer to fix Derefs that are not in the first place
        deref_finder(tcx, body);
    }
}
```

第 85 行 `compute_layout` 计算出 `GeneratorLayout`，并在 111 行保存到 `body.generator` 中。这里的 `GeneratorLayout` 就是 `GeneratorState` 的内存空间，它分成两部分：`prefix` + `variants`。`prefix` 保存了会跨越 `suspend point` 的变量，`variants` 是不同的 state，其中保存了只会在当前 state 使用到的变量。

## GeneratorState 的内存布局是如何计算的？

编译器在代码生成阶段会根据前面计算得到的 `GeneratorLayout` 算出最终的内存布局 `Layout`(compiler/rustc_middle/src/ty/layout.rs):

```rust
/// Compute the full generator layout.
fn generator_layout(
    &self,
    ty: Ty<'tcx>,
    def_id: hir::def_id::DefId,
    substs: SubstsRef<'tcx>,
) -> Result<Layout<'tcx>, LayoutError<'tcx>> {
    use SavedLocalEligibility::*;
    let tcx = self.tcx;
    let subst_field = |ty: Ty<'tcx>| EarlyBinder(ty).subst(tcx, substs);

    let Some(info) = tcx.generator_layout(def_id) else {
        return Err(LayoutError::Unknown(ty));
    };
    let (ineligible_locals, assignments) = self.generator_saved_local_eligibility(&info);

    // Build a prefix layout, including "promoting" all ineligible
    // locals as part of the prefix. We compute the layout of all of
    // these fields at once to get optimal packing.
    let tag_index = substs.as_generator().prefix_tys().count();

    // `info.variant_fields` already accounts for the reserved variants, so no need to add them.
    let max_discr = (info.variant_fields.len() - 1) as u128;
    let discr_int = Integer::fit_unsigned(max_discr);
    let discr_int_ty = discr_int.to_ty(tcx, false);
    let tag = Scalar::Initialized {
        value: Primitive::Int(discr_int, false),
        valid_range: WrappingRange { start: 0, end: max_discr },
    };
    let tag_layout = self.tcx.intern_layout(LayoutS::scalar(self, tag));
    let tag_layout = TyAndLayout { ty: discr_int_ty, layout: tag_layout };

    let promoted_layouts = ineligible_locals
        .iter()
        .map(|local| subst_field(info.field_tys[local]))
        .map(|ty| tcx.mk_maybe_uninit(ty))
        .map(|ty| self.layout_of(ty));
    let prefix_layouts = substs
        .as_generator()
        .prefix_tys()
        .map(|ty| self.layout_of(ty))
        .chain(iter::once(Ok(tag_layout)))
        .chain(promoted_layouts)
        .collect::<Result<Vec<_>, _>>()?;
    let prefix = self.univariant_uninterned(
        ty,
        &prefix_layouts,
        &ReprOptions::default(),
        StructKind::AlwaysSized,
    )?;

    let (prefix_size, prefix_align) = (prefix.size, prefix.align);

    // Split the prefix layout into the "outer" fields (upvars and
    // discriminant) and the "promoted" fields. Promoted fields will
    // get included in each variant that requested them in
    // GeneratorLayout.
    debug!("prefix = {:#?}", prefix);
    let (outer_fields, promoted_offsets, promoted_memory_index) = match prefix.fields {
        FieldsShape::Arbitrary { mut offsets, memory_index } => {
            let mut inverse_memory_index = invert_mapping(&memory_index);

            // "a" (`0..b_start`) and "b" (`b_start..`) correspond to
            // "outer" and "promoted" fields respectively.
            let b_start = (tag_index + 1) as u32;
            let offsets_b = offsets.split_off(b_start as usize);
            let offsets_a = offsets;

            // Disentangle the "a" and "b" components of `inverse_memory_index`
            // by preserving the order but keeping only one disjoint "half" each.
            // FIXME(eddyb) build a better abstraction for permutations, if possible.
            let inverse_memory_index_b: Vec<_> =
                inverse_memory_index.iter().filter_map(|&i| i.checked_sub(b_start)).collect();
            inverse_memory_index.retain(|&i| i < b_start);
            let inverse_memory_index_a = inverse_memory_index;

            // Since `inverse_memory_index_{a,b}` each only refer to their
            // respective fields, they can be safely inverted
            let memory_index_a = invert_mapping(&inverse_memory_index_a);
            let memory_index_b = invert_mapping(&inverse_memory_index_b);

            let outer_fields =
                FieldsShape::Arbitrary { offsets: offsets_a, memory_index: memory_index_a };
            (outer_fields, offsets_b, memory_index_b)
        }
        _ => bug!(),
    };

    let mut size = prefix.size;
    let mut align = prefix.align;
    let variants = info
        .variant_fields
        .iter_enumerated()
        .map(|(index, variant_fields)| {
            // Only include overlap-eligible fields when we compute our variant layout.
            let variant_only_tys = variant_fields
                .iter()
                .filter(|local| match assignments[**local] {
                    Unassigned => bug!(),
                    Assigned(v) if v == index => true,
                    Assigned(_) => bug!("assignment does not match variant"),
                    Ineligible(_) => false,
                })
                .map(|local| subst_field(info.field_tys[*local]));

            let mut variant = self.univariant_uninterned(
                ty,
                &variant_only_tys
                    .map(|ty| self.layout_of(ty))
                    .collect::<Result<Vec<_>, _>>()?,
                &ReprOptions::default(),
                StructKind::Prefixed(prefix_size, prefix_align.abi),
            )?;
            variant.variants = Variants::Single { index };

            let FieldsShape::Arbitrary { offsets, memory_index } = variant.fields else {
                bug!();
            };

            // Now, stitch the promoted and variant-only fields back together in
            // the order they are mentioned by our GeneratorLayout.
            // Because we only use some subset (that can differ between variants)
            // of the promoted fields, we can't just pick those elements of the
            // `promoted_memory_index` (as we'd end up with gaps).
            // So instead, we build an "inverse memory_index", as if all of the
            // promoted fields were being used, but leave the elements not in the
            // subset as `INVALID_FIELD_IDX`, which we can filter out later to
            // obtain a valid (bijective) mapping.
            const INVALID_FIELD_IDX: u32 = !0;
            let mut combined_inverse_memory_index =
                vec![INVALID_FIELD_IDX; promoted_memory_index.len() + memory_index.len()];
            let mut offsets_and_memory_index = iter::zip(offsets, memory_index);
            let combined_offsets = variant_fields
                .iter()
                .enumerate()
                .map(|(i, local)| {
                    let (offset, memory_index) = match assignments[*local] {
                        Unassigned => bug!(),
                        Assigned(_) => {
                            let (offset, memory_index) =
                                offsets_and_memory_index.next().unwrap();
                            (offset, promoted_memory_index.len() as u32 + memory_index)
                        }
                        Ineligible(field_idx) => {
                            let field_idx = field_idx.unwrap() as usize;
                            (promoted_offsets[field_idx], promoted_memory_index[field_idx])
                        }
                    };
                    combined_inverse_memory_index[memory_index as usize] = i as u32;
                    offset
                })
                .collect();

            // Remove the unused slots and invert the mapping to obtain the
            // combined `memory_index` (also see previous comment).
            combined_inverse_memory_index.retain(|&i| i != INVALID_FIELD_IDX);
            let combined_memory_index = invert_mapping(&combined_inverse_memory_index);

            variant.fields = FieldsShape::Arbitrary {
                offsets: combined_offsets,
                memory_index: combined_memory_index,
            };

            size = size.max(variant.size);
            align = align.max(variant.align);
            Ok(tcx.intern_layout(variant))
        })
        .collect::<Result<IndexVec<VariantIdx, _>, _>>()?;

    size = size.align_to(align.abi);

    let abi =
        if prefix.abi.is_uninhabited() || variants.iter().all(|v| v.abi().is_uninhabited()) {
            Abi::Uninhabited
        } else {
            Abi::Aggregate { sized: true }
        };

    let layout = tcx.intern_layout(LayoutS {
        variants: Variants::Multiple {
            tag,
            tag_encoding: TagEncoding::Direct,
            tag_field: tag_index,
            variants,
        },
        fields: outer_fields,
        abi,
        largest_niche: prefix.largest_niche,
        size,
        align,
    });
    debug!("generator layout ({:?}): {:#?}", ty, layout);
    Ok(layout)
}
```

`LayoutS` 的定义为：

```Rust
#[derive(PartialEq, Eq, Hash, HashStable_Generic)]
pub struct LayoutS<'a> {
    /// Says where the fields are located within the layout.
    pub fields: FieldsShape,

    /// Encodes information about multi-variant layouts.
    /// Even with `Multiple` variants, a layout still has its own fields! Those are then
    /// shared between all variants. One of them will be the discriminant,
    /// but e.g. generators can have more.
    ///
    /// To access all fields of this layout, both `fields` and the fields of the active variant
    /// must be taken into account.
    pub variants: Variants<'a>,

    /// The `abi` defines how this data is passed between functions, and it defines
    /// value restrictions via `valid_range`.
    ///
    /// Note that this is entirely orthogonal to the recursive structure defined by
    /// `variants` and `fields`; for example, `ManuallyDrop<Result<isize, isize>>` has
    /// `Abi::ScalarPair`! So, even with non-`Aggregate` `abi`, `fields` and `variants`
    /// have to be taken into account to find all fields of this layout.
    pub abi: Abi,

    /// The leaf scalar with the largest number of invalid values
    /// (i.e. outside of its `valid_range`), if it exists.
    pub largest_niche: Option<Niche>,

    pub align: AbiAndPrefAlign,
    pub size: Size,
}
```

根据定义，`fields` + `variants` 组成了 `GeneratorState` 的内存布局：

```
To access all fields of this layout, both `fields` and the fields of the active variant must be taken into account.
```

在 `generator_layout` 函数中，`fields` 是 `outer_fields`，variants 是 `Variant::Multiple` 的实例，其中保存了 `variants` 和一个 `tag_field`。`outer_fields` 和 `variants` 均由 `prefix` 计算得到：

```rust
// Split the prefix layout into the "outer" fields (upvars and
// discriminant) and the "promoted" fields. Promoted fields will
// get included in each variant that requested them in
// GeneratorLayout
```

`prefix` 的计算方式为：

```rust
let tag_layout = self.tcx.intern_layout(LayoutS::scalar(self, tag));
let tag_layout = TyAndLayout { ty: discr_int_ty, layout: tag_layout };

let promoted_layouts = ineligible_locals
    .iter()
    .map(|local| subst_field(info.field_tys[local]))
    .map(|ty| tcx.mk_maybe_uninit(ty))
    .map(|ty| self.layout_of(ty));
let prefix_layouts = substs
    .as_generator()
    .prefix_tys()
    .map(|ty| self.layout_of(ty))
    .chain(iter::once(Ok(tag_layout)))
    .chain(promoted_layouts)
    .collect::<Result<Vec<_>, _>>()?;
let prefix = self.univariant_uninterned(
    ty,
    &prefix_layouts,
    &ReprOptions::default(),
    StructKind::AlwaysSized,
)?;
```

其中 `prefix_tys()` 返回的就是前面提到的 `upvars`：

```rust
/// This is the types of the fields of a generator which are not stored in a
/// variant.
#[inline]
pub fn prefix_tys(self) -> impl Iterator<Item = Ty<'tcx>> {
    self.upvar_tys()
}
```

因此，一个 `GeneratorState` 的 `Layout` 中会包含一个 `tag`，`upvars`，以及由不同 state 组成的 `variants`。回到 `root_heartbeat` 的例子，`streaming()` 中，除了 `request` 和 `response` 外，还会保存下参数中的 `request: Request<S>`，`path` 和 `codec`。

- `codec`: `tonic::codec::ProstCodec<engula_api::server::v1::HeartbeatRequest, engula_api::server::v1::HeartbeatResponse>` size 0 bytes
- `request`: `tonic::Request<futures::stream::Once<futures::future::Ready<engula_api::server::v1::HeartbeatRequest>>>` size 144 bytes
- `path`: `http::uri::path::PathAndQuery` size 40 bytes
- tag: u8

最终的大小为：self(8 bytes) + request(144 bytes) + path(40 bytes) + uri(88 bytes) + request(240 bytes, http request) + response(32 bytes) + tag(1 byte, aligned to 8) = 560

> 此处 `uri` 是前面计算漏掉的变量。

由于 `async fn` 的参数作为 captured variable，会放置在 `outer_fields` 中。如果一个非常大的参数层层传递到内部的某个 `async fn`，会被一层层放大，最终导致 `Future` 大小呈现指数增长。 19 年有一个 issue 已经指出了这个问题[^1]。

# 解决方案？

对于普通开发者，临时的解决办法有两点：

1. 避免 pass by value，可以使用 `Arc` 或者 reference
2. 减少使用 `async fn`。对于 tail calling，可以直接使用 `impl Future`，避免无意义的 `await`。对于状态不复杂的 `async fn`，也可以考虑手写 `Future::poll()`。

> cpp 提供了右值引用，这类层层传递的变量可以被自然地优化；而 rust 依靠编译器优化，就得依靠生成的代码能满足优化的前置条件。

当然，community 也有人提供了改进方案[^2]。该方案可以简述如下：即将 upvars 保存到 `GeneratorState` 的 `unresumed` state 中 （每个 `GenerateState` 至少有三种 state: `unresumed`, `finished`, `paniced`, 以及用户定义的 `suspent_x`)。

不过因为 rust 编译器架构改成了 demand-deriven compilation，该方案碰到了 query 循环依赖的问题，
需要等待其他人先将修复 dest prop [^3]。

[^1]: https://github.com/rust-lang/rust/issues/62958
[^2]: https://github.com/rust-lang/rust/pull/89213
[^3]: https://github.com/rust-lang/rust/pull/96451
