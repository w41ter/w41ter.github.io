---
layout: post
title: LeetCode - 32 Longest Valid Parenthess
date: 2017-03-13 12:55:22
tags:
    - Algorithm
    - LeetCode
categories: LeetCode

---

# problem 

[Longest Valid Parenthess](https://leetcode.com/problems/longest-valid-parentheses/#/description)

<!-- more -->

# solution

`((())))())())(()())`，如果把这个中所有符合条件的找出来：

```
((()))   ) () ) (()())
```

此时发现单独出现的 `)` 是作为分隔符出现的。只要统计 `)` 出现的次数就可以得到解。

# code 

```
class Solution {
public:
    int longestValidParentheses(string s) {
        int n = s.length(), longest = 0;
        stack<int> st;
        for (int i = 0; i < n; i++) {
            if (s[i] == '(') st.push(i);
            else {
                if (!st.empty()) {
                    if (s[st.top()] == '(') st.pop();
                    else st.push(i);
                }
                else st.push(i);
            }
        }
        if (st.empty()) longest = n;
        else {
            int a = n, b = 0;
            while (!st.empty()) {
                b = st.top(); st.pop();
                longest = max(longest, a-b-1);
                a = b;
            }
            longest = max(longest, a);
        }
        return longest;
    }
};
```

