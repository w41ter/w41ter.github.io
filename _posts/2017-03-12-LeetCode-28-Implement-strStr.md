---
layout: post
title: LeetCode - 28 Implement strStr()
date: 2017-03-12 15:28:14
tags: 
    - Algorithm
    - LeetCode
categories: LeetCode

---

# problem 

[Implement strStr](https://leetcode.com/problems/implement-strstr/)

<!-- more -->

# solution

这道题很明显使用 mp 算法进行字符串匹配。

## MP 算法

假设原字符串：`abbaabbaaba`, 匹配字符串 `abbaaba`。现在我们要从原字符串中找到第一个满足匹配字符串的位置。一般的算法是匹配失败后从新开始匹配：

```
abbaabbaaba
匹配过程：
abbaab|x
 x
  x
   ax
    ab|baaba
```

这种办法效率并不高，并不能利用我们已经知道的信息。观察有两个竖线分割开的部分，两部分左边有相同部分，如何把这部分信息利用起来就是 MP 算法的工作。

这里已经知道了匹配过程中失败了我们可以使用前缀信息来跳过部分无用匹配。现在将匹配字符串 `abbaaba` 的前缀展开：

```
1   a
2   ab
3   abb
4   abba
5   abbaa
6   abbaab
7   abbaaba
```

可以发现：

1. 与 4 后缀匹配的最长前缀是 1
2. 与 4 后缀匹配的最长前缀是 1
3. 与 6 后缀匹配的最长前缀是 2
4. 与 7 后缀匹配的最长前缀是 1

如何计算呢？假设 `prefix[i]` 表示i匹配的最长前缀是第几个，那么有：

1. 对于 i=1 时，没有任何前缀；
2. 当 i>1 时，等于i-1的最长前缀的下一个字符和当前字符进行判断的结果

为了方便将定义改为 `fail[i+1]` 表示i匹配的最长前缀的下一个字符所在位置，所以计算fail的代码如下：

```
vector<int> getNext(string &str) {
    vector<int> failed(str.size()+1, 0);
    for (int i = 1; i < str.size(); ++i) {
        int j = failed[i];
        while (j && str[j] != str[i]) j = failed[j];
        failed[i+1] = str[j] == str[i] ? j+1 : 0;
    }
    return failed;
}
```

如果匹配失败了，我们还可以继续以前缀的最长前缀继续寻找知道没有任何匹配前缀。

有了前缀后，就可以使用fail计算最长匹配。

# code

```
class Solution {
public:
    int strStr(string haystack, string needle) {
        if (needle.empty()) return 0;
        
        vector<int> failed = getNext(needle);
        int j = 0;
        for (int i = 0; i < haystack.size(); ++i) {
            while (j && haystack[i] != needle[j]) j = failed[j];
            if (haystack[i] == needle[j]) j++;
            if (j == needle.size()) return i-j+1;
        }
        return -1;
    }
    
    vector<int> getNext(string &str) {
        vector<int> failed(str.size()+5, 0);
        for (int i = 1; i < str.size(); ++i) {
            int j = failed[i];
            while (j && str[j] != str[i]) j = failed[j];
            failed[i+1] = str[j] == str[i] ? j+1 : 0;
        }
        return failed;
    }
};
```
