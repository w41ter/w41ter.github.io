---
title: LeetCode - 11-Container With Most Water
date: 2017-03-07 12:41:38
tags: 
    - Algorithm 
    - LeetCode
categories: LeetCode
---

# problem

[Container With Most Water](https://leetcode.com/problems/container-with-most-water/?tab=Description)

<!-- more -->

# solution

这道题目直观的解法是每对线都比较一次，直到最大的：

```
class Solution {
public:
    int maxArea(vector<int>& height) {
        int m = 0;
        for (int i = 0; i < height.size()-1; ++i) {
            for (int j = 1; j < height.size(); ++j) {
                int value = (j-i) * min(height[i], height[j]);
                if (value > m)
                    m = value;
            }
        }
        return m;
    }
    
    int min(int l, int r) {
        return l < r ? l : r;
    }
};
```

这样效率肯定不够高，会超时。

我们换一个角度来看，容积取决于最短的线。那么容积中最短的线，其与最远距离的乘积为容量。重复此操作就可以找到最大容积。所以问题就变成了求 a 到左边和右边最远的>= a的点的距离。这个仍然不好求，换个角度来看，就是求a点出发，所有小于等于a的点的最大值。

```
class Solution {
public:
    struct Point {
        int idx;
        int height;
        bool operator < (const Point &rhs) const {
            return height > rhs.height || (height == rhs.height && idx > rhs.idx);
        }
    };
    
    void fill(priority_queue<Point> &queue, const vector<int> &height) {
        for (size_t i = 0; i < height.size(); ++i) {
            queue.push(Point{i, height[i]});
        }
    }
    
    int maxArea(vector<int>& height) {
        priority_queue<Point> left;
        fill(left, height);
        
        priority_queue<Point> right = left;
        
        int size = height.size(), result = 0;
        for (int i = 0; i < size - 1; ++i) {
            while (!left.empty()) {
                Point point = left.top();
                if (point.height > height[i])
                    break;
                left.pop();
                result = max(result, (point.idx - i) * point.height);
            }
        }
        for (int i = size - 1; i > 0; --i) {
            while (!right.empty()) {
                Point point = right.top();
                if (point.height > height[i])
                    break;
                right.pop();
                result = max(result, (i - point.idx) * point.height);
            }
        }
        return result;
    }
};
```

这样的算法肯定能够通过测试了。但是仍然不够快，为什么？因为我们这种办法求出了所有的点能组成的最大值，然而题目中只要求最大的。现在考虑一种情况，如果比a小的且离a最远的旁边还有值，那么意味着所有针对a的计算全是白费的（想想为什么）。

根据刚才的启示，在 a 和 b 的中间，除非有两个大于 a 和 b 的值，否则 a 与 b 最大（想想为什么）。不过话说回来，这么简单的思路为什么一开始想不到呢？

# code

```
class Solution {
public:
    int maxArea(vector<int>& height) {
        int water = 0;
        int i = 0, j = height.size() - 1;
        while (i < j) {
            int h = min(height[i], height[j]);
            water = max(water, (j - i) * h);
            while (height[i] <= h && i < j) i++;
            while (height[j] <= h && i < j) j--;
        }
        return water;
    }
}
```