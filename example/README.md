# fast_build_runner example

`fast_build_runner` is a CLI package, so the main example is running the
installed executable:

```bash
dart pub global activate fast_build_runner
fast_build_runner watch
```

For one-shot builds:

```bash
fast_build_runner build --delete-conflicting-outputs
```
