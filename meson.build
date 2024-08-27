project(
  'com.cassidyjames.butler',
  'vala', 'c',
  version: '1.2.0',
  meson_version: '>=1.1',
)

app_id = meson.project_name()
app_name = 'Butler'

profile = get_option('profile')
if profile == 'devel'
  app_id += '.Devel'
  app_name += ' (Devel)'
endif

summary({
  'Profile': profile,
}, section: 'Development')

config_include = include_directories('.')

config = configuration_data()
config.set_quoted('APP_ID', app_id)
config.set_quoted('APP_NAME', app_name)
config.set_quoted('VERSION', meson.project_version())
config.set_quoted('PROFILE', profile)

config_file = configure_file(
  input: 'src/Config.vala.in',
  output: '@BASENAME@',
  configuration: config
)

gnome = import('gnome')
add_global_arguments('-DGETTEXT_PACKAGE="@0@"'.format(app_id), language:'c')

subdir('data')
subdir('src')

meson.add_install_script('build-aux' / 'meson'/ 'post_install.py')
