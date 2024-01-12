install_data(
  'icons' / 'app.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps'),
  rename: meson.project_name() + '.svg'
)

install_data(
  'icons' / 'symbolic.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'symbolic', 'apps'),
  rename: meson.project_name() + '-symbolic.svg'
)

install_data(
  'gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
  rename: meson.project_name() + '.gschema.xml'
)

install_data(
  'launcher.desktop',
  install_dir: get_option('datadir') / 'applications',
  rename: meson.project_name() + '.desktop'
)

install_data(
  'metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo',
  rename: meson.project_name() + '.metainfo.xml'
)
