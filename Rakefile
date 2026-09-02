# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/**/test_*.rb']
  t.warning = false
end

desc 'Run the application (BACKEND=json|vcard)'
task :run do
  sh "ruby bin/gnome-contacts-rb #{ENV.fetch('BACKEND', 'json')}"
end

task default: :test
