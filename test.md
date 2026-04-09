# 一级标题 H1

## 二级标题 H2

### 三级标题 H3

#### 四级标题 H4

##### 五级标题 H5

###### 六级标题 H6

---

## 段落与换行

这是一个普通段落。Markdown 编辑器需要支持中英文混排：The quick brown fox jumps over the lazy dog.

这是另一个段落，前面有空行分隔。  
这一行末尾有两个空格,应当渲染为软换行。

---

## 文本格式

**粗体** 和 __另一种粗体__。

*斜体* 和 _另一种斜体_。

***粗斜体*** 同时生效。

~~删除线~~ 文本。

行内 `code` 片段：`let x = 42`。

可以组合：**加粗里有 `code` 和 *斜体***。

---

## 链接

无 scheme 链接（编辑器应自动补 https）：[百度](www.baidu.com)

完整链接：[Google](https://google.com)

带 title：[Apple](https://apple.com "Apple 官网")

自动链接：<https://github.com>

邮件：<test@example.com>

引用式链接：[点这里][ref-1]

[ref-1]: https://example.com "Example"

---

## 图片

![占位图](https://via.placeholder.com/150 "占位图标题")

引用式图片：![logo][img-ref]

[img-ref]: https://via.placeholder.com/100

---

## 列表

### 无序列表

- 第一项
- 第二项
  - 嵌套 A
  - 嵌套 B
    - 更深一层
- 第三项

### 有序列表

1. 第一步
2. 第二步
   1. 子步骤
   2. 子步骤
3. 第三步

### 任务列表（GFM）

- [x] 已完成的事项
- [x] 另一件已完成
- [ ] 未完成
- [ ] 还没做

### 混合列表

1. 有序父项
   - 无序子项
   - [ ] 任务子项
2. 第二个有序项

---

## 引用

> 这是一个引用块。
>
> 引用可以有多个段落。
>
> > 嵌套引用看起来像这样。
> >
> > > 还能再嵌一层。

> **提示**：引用里也支持其它格式，比如 *斜体*、`code`、[链接](https://example.com)。

---

## 代码块

行内代码：`printf("hello")`

无语言标识的代码块：

```
plain text code block
no syntax highlight
```

Swift：

```swift
import Foundation

struct Point {
    var x: Double
    var y: Double

    func distance(to other: Point) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

let p = Point(x: 3, y: 4)
print(p.distance(to: Point(x: 0, y: 0)))
```

JavaScript：

```javascript
const fib = n => {
  if (n < 2) return n;
  return fib(n - 1) + fib(n - 2);
};

console.log([0, 1, 2, 3, 4, 5].map(fib));
```

Python：

```python
def quicksort(arr):
    if len(arr) <= 1:
        return arr
    pivot = arr[len(arr) // 2]
    left = [x for x in arr if x < pivot]
    mid = [x for x in arr if x == pivot]
    right = [x for x in arr if x > pivot]
    return quicksort(left) + mid + quicksort(right)

print(quicksort([3, 6, 1, 8, 2, 9, 4]))
```

Shell：

```sh
#!/usr/bin/env bash
set -euo pipefail
for f in *.md; do
  echo "Processing $f"
  wc -l "$f"
done
```

---

## 表格（GFM）

| 语言       | 类型       | 出现年份 |
| ---------- | ---------- | -------- |
| Swift      | 编译型     | 2014     |
| JavaScript | 解释型     | 1995     |
| Python     | 解释型     | 1991     |
| Rust       | 编译型     | 2010     |

对齐方式：

| 左对齐 | 居中 | 右对齐 |
| :----- | :--: | -----: |
| a      |  b   |      c |
| 长一点 |  中  |   1234 |
| x      |  y   |      z |

---

## 分隔线

上面是内容。

---

下面是内容。

***

下面是另一段。

___

---

## HTML 内联

这里有一段 <strong>HTML 加粗</strong> 和 <em>HTML 斜体</em>。

<details>
<summary>点击展开</summary>

折叠内容里也可以放 **markdown**：

- 列表项 1
- 列表项 2

</details>

---

## 转义字符

\*这不是斜体\*，反斜杠用于转义：\\ \` \* \_ \{ \} \[ \] \( \) \# \+ \- \. \!

---

## 数学 / 特殊字符

版权 © 注册 ® 商标 ™ 度数 ° 加减 ± 不等于 ≠ 约等于 ≈ 无穷 ∞

箭头：← → ↑ ↓ ⇐ ⇒

---

## 长内容混排

> **小结**：这个文件用来验证 AropytEditor 的预览渲染是否覆盖了常见 markdown 语法。
> 如果以下任意一项渲染异常，就该回到 `MarkdownRenderer.swift` 检查模板。

1. **标题** 1~6 级是否字号正确
2. **链接** Cmd+点击是否能打开浏览器（包括 `www.foo.com` 这种无 scheme 写法）
3. **代码块** 是否有 highlight.js 高亮 + 圆角背景
4. **表格** 是否对齐、有边框
5. **任务列表** 复选框是否渲染
6. **引用** 嵌套层级是否有缩进
7. **图片** 是否能加载远程 URL
8. **删除线 / 粗斜体** 等组合格式是否生效
