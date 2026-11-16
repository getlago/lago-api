# frozen_string_literal: true

# A Kubernetes emptyDir mounted at /tmp is mode 2777 without the sticky bit.
# Dir.tmpdir refuses such a directory ("could not find a temporary directory"),
# so Puma cannot spool a large request body. Use a private 0700 directory in it.
if ENV["TMPDIR"].nil? && File.directory?("/tmp") && File.world_writable?("/tmp") && !File.sticky?("/tmp")
  tmpdir = "/tmp/ruby-#{Process.uid}"
  begin
    Dir.mkdir(tmpdir, 0o700)
  rescue Errno::EEXIST
    nil
  end
  ENV["TMPDIR"] = tmpdir
end

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
