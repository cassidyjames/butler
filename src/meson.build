executable(
  app_id,
  'App.vala',
  'MainWindow.vala',
  'Utils.vala',
  'Widgets' / 'WebView.vala',
  asresources,
  config_file,
  include_directories: config_include,
  dependencies: [
    dependency('glib-2.0'),
    dependency('gtk4'),
    dependency('libadwaita-1', version: '>=1.6'),
    dependency('webkitgtk-6.0'),
    meson.get_compiler('c').find_library('m'), # GLib.Math
    meson.get_compiler('vala').find_library('posix'),
  ],
  install: true
)
