# frozen_string_literal: true

# kettle-jem:freeze
# To retain chunks of comments & code during kettle-jem templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# kettle-jem will then preserve content between those markers across template runs.
# kettle-jem:unfreeze

source 'https://rubygems.org'

git_source(:codeberg) { |repo_name| "https://codeberg.org/#{repo_name}" }
git_source(:gitlab) { |repo_name| "https://gitlab.com/#{repo_name}" }

#### IMPORTANT #######################################################
# Gemfile is for local development ONLY; Gemfile is NOT loaded in CI #
####################################################### IMPORTANT ####

# Include dependencies from gnome-contacts-rb.gemspec
gemspec

gem "kettle-family", "~> 1.3", ">= 1.3.29"

# Local workspace dependency wiring for *_local.gemfile overrides
gem "nomono", "~> 1.1", ">= 1.1.14", require: false # ruby >= 3.2.0

# Templating and the StructuredMerge family share this modular Gemfile.
# kettle-jem needs StructuredMerge to template, and kettle-changelog needs it at
# runtime (ast-crispr-markdown-markly -> markdown-merge -> tree_haver), so the
# test, lint, and release bundles resolve the family too. While the family is
# only partially released, registry copies pin the last published version exactly
# and cannot be satisfied alongside a local lockstep version, so a partial local
# wiring fails version solving for every command in the bundle.
#
# (env-switched: STRUCTUREDMERGE_DEV=/path/to/structuredmerge/ruby/gems for local paths)
eval_gemfile "gemfiles/modular/templating.gemfile" if
  ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero? ||
  ENV.fetch("STRUCTUREDMERGE_DEV", "false").casecmp("false") != 0

# Debugging
eval_gemfile "gemfiles/modular/debug.gemfile"

# Code Coverage (env-switched: KETTLE_DEV_DEV=true for local paths)
eval_gemfile "gemfiles/modular/coverage.gemfile"

# Linting
eval_gemfile "gemfiles/modular/style.gemfile"

# Documentation
eval_gemfile "gemfiles/modular/documentation.gemfile"

# Changelog release tooling (available on Ruby versions supported by kettle-changelog)
eval_gemfile "gemfiles/modular/changelog.gemfile"

# Optional
eval_gemfile "gemfiles/modular/optional.gemfile"

### Std Lib Extracted Gems
eval_gemfile "gemfiles/modular/x_std_libs.gemfile"

# See unlocked_deps appraisal for more details on irb inclusion
gem "irb", "~> 1.17" # ruby >= 2.7
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
gem "gtk4"
gem "adwaita"
