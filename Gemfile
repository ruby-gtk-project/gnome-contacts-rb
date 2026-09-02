# frozen_string_literal: true

source 'https://rubygems.org'

# libadwaita bindings; pulls in gtk4, glib2, cairo and friends.
# Building this gem needs libadwaita-1's development files on PKG_CONFIG_PATH.
gem 'adwaita', '~> 4.3'

# QR code generation for the "Share as QR Code" dialog. Upstream links against
# libqrencode, which has no Ruby binding; rqrcode_core is pure Ruby and the
# modules are painted with Cairo the same way upstream paints its pixel buffer.
gem 'rqrcode_core', '~> 2.0'

group :development, :test do
  gem 'minitest', '~> 5.0'
  gem 'rake', '~> 13.0'
end

gem "gem_kit"
