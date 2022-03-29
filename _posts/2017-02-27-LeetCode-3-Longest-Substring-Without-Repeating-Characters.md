---
layout: post
title: LeetCode - 3-Longest Substring Without Repeating Characters
date: 2017-02-27 17:30:31
tags: 
    - LeetCode 
    - Algorithm 
categories: LeetCode

---

## problem

[Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/?tab=Description)

<!-- more -->

## solution

1. 对于一个没有重复的字符串，加入一个新字符，长度+1
2. 如果加入的字符已经存在，那么找到字符串中冲突字符后的字符串，构成新的未重复字符串

需要注意的是我开始潜意识认为字符串指“a-z”,实际上还包含“！@”之类的字符

## code

```
int lengthOfLongestSubstring(string str) {
    if (str.size() == 0 || str.size() == 1)
        return str.size();
    
    int left = 0, right = 1;    // [left, right)
    int index[128] = {1}, length = 1;
    
    index[str[left]] = 1;
    while (right < str.size()) {
        char a = str[right];
        
        if (index[a] == 0) {   // without
            index[a] = 1;         // add
        }
        else {
            while (str[left] != a) {
                index[str[left]] = 0;  // del
                left++;
            }
            left++;
        }
        
        right++;
        
        int current = right - left;
        if (length < current) 
            length = current;
    }
    return length;
}
```
