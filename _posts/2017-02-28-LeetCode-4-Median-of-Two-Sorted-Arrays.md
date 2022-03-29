---
layout: post
title: LeetCode - 4-Median of Two Sorted Arrays
date: 2017-02-28 20:14:02
tags: 
    - LeetCode 
    - Algorithm 
categories: LeetCode

---

## problem

[Median of Two Sorted Arrays](https://leetcode.com/problems/median-of-two-sorted-arrays/?tab=Description)

<!-- more -->

## solution

这道题目没能做出来，从网上找到了题解。题解是将问题转换为寻找第K小的数，且边际情况非常少。

首先假设数组A和B的元素个数都大于k/2，我们比较A的第k/2小的元素和B的第k/2小的元素A[k/2-1]和B[k/2-1]。

如果A[k/2-1]<B[k/2-1]，这表示A[0]到A[k/2-1]的元素都在A和B合并之后的前k小的元素中。换句话说，A[k/2-1]不可能大于两数组合并之后的第k小值，所以我们可以将其抛弃。证明：假设A[k/2-1]大于合并之后的第k小值，我们不妨假定其为第（k+1）小值。由于A[k/2-1]小于B[k/2-1]，所以B[k/2-1]至少是第（k+2）小值。但实际上，在A中至多存在k/2-1个元素小于A[k/2-1]，B中也至多存在k/2-1个元素小于A[k/2-1]，所以小于A[k/2-1]的元素个数至多有k/2+ k/2-2，小于k，这与A[k/2-1]是第（k+1）的数矛盾。

当A[k/2-1]>B[k/2-1]时存在类似的结论。

当A[k/2-1]=B[k/2-1]时，我们已经找到了第k小的数，也即这个相等的元素，我们将其记为m。由于在A和B中分别有k/2-1个元素小于m，所以m即是第k小的数。(这里可能有人会有疑问，如果k为奇数，则m不是中位数。这里是进行了理想化考虑，在实际代码中略有不同，是先求k/2，然后利用k-k/2获得另一个数。)

通过上面的分析，我们即可以采用递归的方式实现寻找数组A和B的元素个数都大于k/2时第k小的数。对于另一种情况，使用min(k / 2, A.size)和k-k/2且保证A.size<B.size那么就可以转为前面的条件。

此外我们还需要考虑几个边界条件：

. 如果A或者B为空，则直接返回B[k-1]或者A[k-1]；
. 如果k为1，我们只需要返回A[0]和B[0]中的较小值；
. 如果A[k/2-1]=B[k/2-1]，返回其中一个；

## code 

```
double findKth(int a[], int m, int b[], int n, int k)  
{  
    //always assume that m is equal or smaller than n  
    if (m > n)  
        return findKth(b, n, a, m, k);  
    if (m == 0)  
        return b[k - 1];  
    if (k == 1)  
        return min(a[0], b[0]);  
    //divide k into two parts  
    int pa = min(k / 2, m), pb = k - pa;  
    if (a[pa - 1] < b[pb - 1])  
        return findKth(a + pa, m - pa, b, n, k - pa);  
    else if (a[pa - 1] > b[pb - 1])  
        return findKth(a, m, b + pb, n - pb, k - pb);  
    else  
        return a[pa - 1];  
}

class Solution {
public:
    double findMedianSortedArrays(vector<int>& nums1, vector<int>& nums2) {
        int *A = nums1.data(), m = nums1.size(), *B = nums2.data(), n = nums2.size();
        int total = m + n;  
        if (total & 0x1)  
            return findKth(A, m, B, n, total / 2 + 1);  
        else  
            return (findKth(A, m, B, n, total / 2)  
                    + findKth(A, m, B, n, total / 2 + 1)) / 2;
    }
};
```