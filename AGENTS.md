* check docs/ to understand the specification
  * docs/spec.md
  * docs/todo.md
* When modifying the source code
  * add tests
  * update docs/
    * catch up changes
    * move completed tasks to done.md
  * commit it

## Debugging (Lumitrace)
lumitrace is a tool that records runtime values of each Ruby expression.
When a test fails, read `lumitrace help` first, then use it.
Basic: `lumitrace -t exec rake test`

