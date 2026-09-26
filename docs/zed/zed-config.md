# Zed 配置同步说明

本目录包含 Zed 编辑器的配置文件。

## 配置文件位置与方法

### macOS

```
cp settings.json ~/.config/zed/settings.json
```

### Windows

```
copy /Y settings.json %APPDATA%\zed\settings.json
```

## 注意事项

- Zed 会在重启后加载新的配置
- 如果配置有误，Zed 可以通过删除 `settings.json` 重置为默认设置
- 建议定期备份当前配置
