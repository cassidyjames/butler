data_config = configuration_data()
data_config.set('app_id', app_id)
data_config.set('app_name', app_name)

install_data(
  'icons' / profile + '.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps'),
  rename: app_id + '.svg'
)

install_data(
  'icons' / 'symbolic.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'symbolic', 'apps'),
  rename: app_id + '-symbolic.svg'
)

gschema_file = configure_file(
  input: files('gschema.xml.in'),
  output: app_id + '.gschema.xml',
  configuration: data_config,
  install: true,
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

desktop_file = configure_file(
  input: files('launcher.desktop.in'),
  output: app_id + '.desktop',
  configuration: data_config,
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

metainfo_file = configure_file(
  input: files('metainfo.xml.in'),
  output: '@BASENAME@',
  configuration: data_config,
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
)

asresources = gnome.compile_resources(
  'as-resources',
  'gresource.xml',
  source_dir: 'data',
  c_name: 'as',
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif
