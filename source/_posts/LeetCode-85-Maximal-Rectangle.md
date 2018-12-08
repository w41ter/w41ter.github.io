---
title: LeetCode - 85 Maximal Rectangle
date: 2017-06-12 19:33:29
tags: 
    - Algorithm
    - LeetCode

categories: LeetCode

---

[85. Maximal Rectangle](https://leetcode.com/problems/maximal-rectangle/#/description)

首先看题意，题目需要求出由0和1组成的2Dmatrix中，全由1组成的矩形最大面积为多少。比如下面的矩形：

```
1 0 1 0 0
1 0 1 1 1
1 1 1 1 1
1 0 0 1 0
```

最大面积为 6。

在做这提前，需要看看前一题：[84. Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/#/description)。这道题目是求出柱状图中可以摆放下的最大矩形。

如何求解？仔细观察可以发现，像 `576` 这样的数据，可以看作中间高，两边低。而具体面积则由数据个数 * 选取区间中最矮的高度决定。所以完全可以把这几个变为：`555`、`7`和`66`这样的形式，然后再从中选出最大的。

所以这道题的简单解法是从头到尾扫一次，每次遇到递减时，将多出的部分计算后给扔掉，那么扔掉后的数据则仍然是递增的。比如`576`，当扫描到`6`时，计算得`7`，并将`7`改为`6`，得到`566`继续计算。这样，得到了中间去掉部分能组成的最大面积，和最后剩下的递增数组进行比较。对于单调递增的数据，也好算，减少宽度，增加高度就能算出来。所以代码部分如下：

```
class Solution {
public:
    int largestRectangleArea(vector<int>& heights) {
        stack<int> stack;
        int max_ = 0;
        for (auto i : heights) {
            if (stack.empty())
                stack.push(i);
            else {
                int l = stack.top();
                if (l <= i) {
                    stack.push(i);
                }
                else {
                    int count = 1;
                    while (!stack.empty() && stack.top() > i) {
                        int t = stack.top();
                        stack.pop();
                        if (t * count > max_) {
                            max_ = t * count;
                        }
                        count++;
                    }
                    for (int j = 0; j < count; j++) {
                        stack.push(i);
                    }
                }
            }
        }
        if (!stack.empty()) {
            int count = stack.size();
            for (int i = 1; i <= count; ++i) {
                int t = stack.top();
                stack.pop();
                if (t * i > max_)
                    max_ = t * i;
            }
        }
        return max_;
    }
};
```

现在回到计算matrix中的矩形问题上来。用一行将矩形分割成两半，上面部分和下面部分。遮住下面部分，那么看到的就是一个`Histogram`，则可以使用上面一题的解法来做。将行往下挪，如果出现了(1/0/1)这样的列数据，不再是一个`Histogram`，那么可以认为0以上部分全为0，得到`Histogram`。所以题目答案为：

```
class Solution {
public:
    int maximalRectangle(vector<vector<char>>& matrix) {
        if (matrix.empty() || matrix[0].empty()) return 0;
        int max = 0;
        vector<int> heights(matrix[0].size(), 0);
        for (int i = 0; i < matrix.size(); ++i) {
            for (int j = 0; j < matrix[0].size(); ++j) {
                heights[j] = (matrix[i][j] == '0') ? 0 : heights[j] + 1;
            }
            max = std::max(largestRectangleArea(heights), max);
        }
        return max;
    }
    
    int largestRectangleArea(vector<int>& heights) {
        stack<int> stack;
        int max_ = 0;
        for (auto i : heights) {
            if (stack.empty())
                stack.push(i);
            else {
                int l = stack.top();
                if (l <= i) {
                    stack.push(i);
                }
                else {
                    int count = 1;
                    while (!stack.empty() && stack.top() > i) {
                        int t = stack.top();
                        stack.pop();
                        if (t * count > max_) {
                            max_ = t * count;
                        }
                        count++;
                    }
                    for (int j = 0; j < count; j++) {
                        stack.push(i);
                    }
                }
            }
        }
        if (!stack.empty()) {
            int count = stack.size();
            for (int i = 1; i <= count; ++i) {
                int t = stack.top();
                stack.pop();
                if (t * i > max_)
                    max_ = t * i;
            }
        }
        return max_;
    }
};
```