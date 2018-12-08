---
title: Laravel5.2+Dingo/API+JWTauth 的坑
date: 2016-04-28 17:41:15
tags: PHP
---

最近着手做一款应用后端，在否定了 BaaS 后，决定用 Laravel 框架自己做一个 RESTful API。我的环境是 Laravel 5.2 ，另外使用了 Dingo/API 和 JWTAuth。不过在使用的过程中遇到了很多的坑，所以在这里记录一下。

<!-- more -->

JWTAuth 默认使用 Users 表做为登录认证的表。而我的需求比较奇葩，共有两个不同的表；除此之外，还需要对 JWTAuth 的错误进行自定义。在搜索无果后，只好自己动手实现这两个需求。

首先解决第二个问题，对 JWTAuth 进行错误自定义。这种情况下，我们可以自己去添加一个中间件处理身份认证。

### 添加中间件处理身份验证

1、添加一个 Middleware

可以使用命令行添加：

```
php artisan make:middleware GetUserFromToken
```

此命令将会在 `app/Http/Middleware` 目录内置立一个名称为 `GetUserFromToken` 的类。

2、在 `GetUserFromToken` 中编辑代码，这里仿照 JWTAuth 写了 `Middleware`

```
<?php

namespace App\Http\Middleware;

use Closure;
use JWTAuth;
use Tymon\JWTAuth\Exceptions\JWTException;
use Tymon\JWTAuth\Exceptions\TokenExpiredException;
use Tymon\JWTAuth\Exceptions\TokenInvalidException;

class GetUserFromToken
{
    public function handle($request, Closure $next)
    {
        $auth = JWTAuth::parseToken();
        if (! $token = $auth->setRequest($request)->getToken()) {
            return response()->json([
                'code' => '',
                'message' => 'token_not_provided',
                'data' => '',
            ]);
        }
        
        try {
            $user = $auth->authenticate($token);
        } catch (TokenExpiredException $e) {
            return response()->json([
                'code' => '',
                'message' => 'token_expired',
                'data' => '',
            ]);
        } catch (JWTException $e) {
            return response()->json([
                'code' => '',
                'message' => 'token_invalid',
                'data' => '',
            ]);
        }

        if (! $user) {
            return response()->json([
                'code' => '',
                'message' => 'user_not_found',
                'data' => '',
            ]);
        }

        //$this->events->fire('tymon.jwt.valid', $user);

        return $next($request);
    }
}
```

我将每次错误返回数据替换成自己设置的错误信息。

3、在 `/app/Http/Kernel.php` 中 `$routeMiddleware` 新增如下内容：

```
protected $routeMiddleware = [
    ...
    'jwt.api.auth' => \App\Http\Middleware\GetUserFromToken::class, //新增注册的中间件
];
```

4、在路由中指定使用 `jwt.api.auth`

```
['middleware' => 'jwt.api.auth']
```

完成上面的操作，我们新增处理接口身份认证中间件就完成了。

现在需要处理前一个问题。

### 多表配置

在 JWTAuth 中，可以在配置文件 jwt.php 中设置 `User Model namespace`，所以可以在 `Middleware` 中 `handle` 部分添加如下代码来动态配置 `User Model namespace`

```
config(['jwt.user' => 'App\Models\User']);
```

这里，我把 User 表放到了 `App\Models\` 中和其他的统一进行管理。不过我在测试中一直出现 `App\User` 未定义错误。然后就开始了漫长的定位之旅。首先在访问 `authenticate` 得到

```
public function authenticate($token = false)
{
    $id = $this->getPayload($token)->get('sub');

    if (! $this->auth->byId($id)) {
        return false;
    }

    return $this->auth->user();
}
```

然后，在 `Tymon\JWTAuth\Providers\Auth\IlluminateAuthAdapter` 中找到 `byId` 和 `user` 对应代码如下

```
public function byId($id)
{
    return $this->auth->onceUsingId($id);
}

public function user()
{
    return $this->auth->user();
}
```

经过测试发现 auth 实际上是一个 `Illuminate\Auth\SessionGuard` 实例，然后在其中发现了 `onceUsingId` 和 `user` 部分代码

```
public function onceUsingId($id)
{
    if (! is_null($user = $this->provider->retrieveById($id))) {
        $this->setUser($user);

        return true;
    }

    return false;
}
```

在查找 `provider` 所在位置时定位到文件 `Illuminate\Auth\CreatesUserProviders.php` 中找到如下代码

```
public function createUserProvider($provider)
{
    $config = $this->app['config']['auth.providers.'.$provider];
    if (isset($this->customProviderCreators[$config['driver']])) {
        return call_user_func(
            $this->customProviderCreators[$config['driver']], $this->app, $config
        );
    }

    switch ($config['driver']) {
        case 'database':
            return $this->createDatabaseProvider($config);
        case 'eloquent':
            return $this->createEloquentProvider($config);
        default:
            throw new InvalidArgumentException("Authentication user provider [{$config['driver']}] is not defined.");
    }
}
```

这里通过 `auth.providers.users` 配置设置 `$config`，而 `auth.providers.users` 在文件 auth.php 中默认配置如下

```
'providers' => [
    'users' => [
        'driver' => 'eloquent',
        'model' => App\User::class,
    ],
]
```

所以程序走到了 `return $this->createEloquentProvider($config);` 这一步，继续跟踪得到:

```
protected function createEloquentProvider($config)
{
    return new EloquentUserProvider($this->app['hash'], $config['model']);
}
```

其中 `$config['model']` 则就是原型:

```
public function __construct(HasherContract $hasher, $model)
{
    $this->model = $model;
    $this->hasher = $hasher;
}
```

到此，确定了 `model` 所在位置，只需要在 `Middleware` 中添加如下配置

```
config(['auth.providers.users.model' => \App\Models\User::class]);
```

最终代码如下

```
config(['jwt.user' => '\App\Models\User']);
config(['auth.providers.users.model' => \App\Models\User::class]);
$auth = JWTAuth::parseToken();
if (! $token = $auth->setRequest($request)->getToken()) {
    return response()->json([
        'code' => '',
        'message' => 'token_not_provided',
        'data' => '',
    ]);
}

try {
    $user = $auth->authenticate($token);
} catch (TokenExpiredException $e) {
    return response()->json([
        'code' => '',
        'message' => 'token_expired',
        'data' => '',
    ]);
} catch (JWTException $e) {
    return response()->json([
        'code' => '',
        'message' => 'token_invalid',
        'data' => '',
    ]);
}

if (! $user) {
    return response()->json([
        'code' => '',
        'message' => 'user_not_found',
        'data' => '',
    ]);
}

//$this->events->fire('tymon.jwt.valid', $user);

return $next($request);
```

到这里为止，实现了自定义表名功能，在结合自定义 `Middleware` 部分，就可以实现多表认证。只需要对每一种认证都实现对应的 `Middleware` ，在接口处分别对不同接口使用不同的 `Middleware` 进行验证就好。

当然，这样的实现肯定不完美，因为所有的事件部分代码全部删除了。这部分还没有想到什么好的解决办法，自己实现 event 应该是可行的，这里就么有尝试。
