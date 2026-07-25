# plz

my super-focused UI Library, plz.

it's:

- immediate-mode: so ui always reflects the latest state
- pooled: instance pooling controls instantiation cost
- tight-knit: 90% of the module should be useful for every one of your projects. anything else is intentionally left to you :)

and limited by:

- no support for setting tags, attributes, or calling methods on roblox instances. this is because plz uses instances only for rendering and receiving events, and i have no use for allowing more right now.

if like me you enjoy data-oriented workflows and writing shaders, you may find this project interesting!

## installation

Copy the raw contents of [plz.luau](./plz.luau), and store them in a module somewhere.

## examples

- [`clicker.client.luau`](./examples/clicker.client.luau) - Renders buttons that display a new pulsing bar every time you click them
- [`cube_wave.client.luau`](./examples/cube_wave.client.luau) - Creates an array of parts that move in a sin wave, flashing with alternating highlights. Change the attributes to tweak at runtime.

## 💖prior art

figured it'd be fun to think about all the random projects i've checked out that led up to this ones creation:

| 💖 | ? |
| :--------------- | :--------------- |
| [Iris](https://devforum.roblox.com/t/iris-immediate-mode-ui-library-based-on-dear-imgui/2302802) | Roblox immediate-mode UI research.|
| [Dear ImGui](https://github.com/ocornut/imgui) | Of course :) We also wouldn't have Iris without it!
| [Pangui](https://pangui.io)| Inspiring razor-sharp focus, inspired the 'shader-code' like workflow.
| [Native Legacy](https://github.com/Builder-Pals/native-legacy) | Main test-bed, also got me thinking about more weird uses for object pooling.
| [jecs](https://github.com/Ukendio/jecs) | Got me thinking about data-oriented concepts and entities.