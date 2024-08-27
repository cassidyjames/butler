executable(
  app_id,
  'App.vala',
  'MainWindow.vala',
  'Widgets' / 'WebView.vala',
  asresources,
  config_file,
  include_directories: config_include,
  dependencies: [
    dependency('glib-2.0'),
    dependency('gtk4'),
    dependency('libadwaita-1', version: '>=1.5'),
    dependency('webkitgtk-6.0'),
    meson.get_compiler('vala').find_library('posix'),
  ],
  install: true
)
