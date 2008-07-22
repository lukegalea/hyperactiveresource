# In rails 1.2, plugins aren't available in the path until they're loaded.
# Check to see if the rspec plugin is installed first and require
# it if it is.  If not, use the gem version.
rspec_base = File.expand_path(File.dirname(__FILE__) + '/../../rspec/lib')
$LOAD_PATH.unshift(rspec_base) if File.exist?(rspec_base)
require 'spec/rake/spectask'
require 'spec/translator'

namespace :hyperactive_resource do
  desc "Run all specs for hyperactive resource"
  Spec::Rake::SpecTask.new(:spec) do |t|    
    spec_opts_file = "\"#{RAILS_ROOT}/spec/spec.opts\""
    t.spec_opts = ['--options', spec_opts_file] if File.exist? spec_opts_file
    t.spec_files = FileList['vendor/plugins/hyperactive_resource/spec/*_spec.rb']
  end
end
