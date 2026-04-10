# ImGui Widget Backend Notes

This note captures the useful Dear ImGui Lua wrapper facts we confirmed while building widget geometry in ModpackLib.

Use this as the first reference when adding or reshaping widgets so we do not keep digging through `ReturnOfModdingBase` each time.

## Source of truth

Backend repo:
- `D:\Work\win-projects\modding\ReturnOfModdingBase`

Relevant files:
- `docs/lua/tables/ImGui.md`
- `src/lua/bindings/imgui.hpp`

## Confirmed useful APIs

These are available from the Lua-side ImGui wrapper and are directly relevant to widget geometry/composite controls:

- `ImGui.GetCursorPosX()`
- `ImGui.SetCursorPosX(localX)`
- `ImGui.SameLine()`
- `ImGui.SameLine(offsetFromStartX)`
- `ImGui.Button(label)`
- `ImGui.Button(label, width, height)`
- `ImGui.GetItemRectSize()`
- `ImGui.GetStyle()`
- `ImGui.GetFrameHeight()`
- `ImGui.GetFrameHeightWithSpacing()`
- `ImGui.CalcTextSize(text)`

## What these enable

These are enough to implement:

- absolute horizontal placement inside the current row
- composite widgets built from multiple draw calls
- fixed-width value slots
- centered or right-aligned text inside explicit slots
- button-width estimation from text + style metrics
- post-draw measurement of the last item when needed

They are not a full layout engine. They are enough for precise manual row composition.

## Important backend facts

### `CalcTextSize(...)` returns a tuple

The binding returns:

```lua
width, height = ImGui.CalcTextSize("Text")
```

This matters because test doubles often simplify it to a single numeric width. Real widget code should expect tuple returns from the backend.

### `GetItemRectSize()` returns a tuple

The binding returns:

```lua
width, height = ImGui.GetItemRectSize()
```

Use this only when you truly need the rendered size of the just-drawn item.

### `SameLine(...)` only exposes the one-argument overload to Lua

From the binding export, Lua gets:

- `ImGui.SameLine()`
- `ImGui.SameLine(offsetFromStartX)`

Do not assume the C++ two-argument overload with explicit spacing is exported to Lua just because it exists in Dear ImGui internally.

### `SetCursorPosX(...)` is local to the current window/row context

Treat all widget geometry offsets as local X positions relative to the current row origin, not absolute screen positions.

This matches our ModpackLib geometry contract:

- row-level starts like `controlStart`, `control2Start`, `separatorStart`
- subcontrol starts relative to the enclosing composite control

## Practical guidance for widget authors

### 1. Prefer explicit starts over smart derivation

ImGui is immediate-mode and composite widgets are built from separate items.

So for widget geometry:

- explicit offsets are usually better than hidden layout magic
- derive as little as possible in the hot render path

### 2. Only align text inside an explicit slot

For dynamic numeric text:

- use `valueWidth` only when you want slot alignment
- use `valueAlign = "center"` or `"right"` only with that explicit slot
- use `valueStart` when you want absolute value placement instead

Do not try to infer a value slot from neighboring controls unless there is a very strong reason.

### 3. Composite controls are not native single widgets

A stepper like:

```text
-   4   +
```

is not one native ImGui control. It is separate calls:

- `Button("-")`
- `Text("4")`
- `Button("+")`

That means "control width" is often a misleading abstraction for composite widgets. Think in subcontrol offsets or explicit value slots instead.

### 4. Call `SameLine()` before repositioning on the same row

If a widget draws a label and then repositions the next item:

- call `SameLine()`
- then `SetCursorPosX(...)`

Otherwise the next item can drop to a new line and the X repositioning will not mean what you think it means.

## Suggested minimal mental model

When building new widgets, default to this:

- one row origin
- explicit X starts for meaningful subparts
- optional fixed-width text slot for dynamic text
- no hidden auto-layout beyond what is absolutely necessary

That model matches the backend well and keeps the Lib surface understandable.

## Known caution

Our current Lib test doubles are more permissive/simplified than the real backend in at least one important way:

- test doubles often return a scalar from `CalcTextSize(...)`
- the real backend returns `(width, height)`

When changing text measurement code, verify against the backend contract, not just the tests.
