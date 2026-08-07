# frozen_string_literal: true

# The v2 catalog REST surface is gated on the organization's product_catalog
# feature flag; enable it transparently for every v2 request spec so each
# file does not have to repeat the flag setup.
RSpec.configure do |config|
  config.before(type: :request) do |example|
    # rerun_file_path points at the outermost spec file even for examples
    # defined inside shared example groups.
    next unless example.metadata[:rerun_file_path].include?("requests/api/v2")
    next if example.metadata[:product_catalog] == false
    next unless respond_to?(:organization)

    org = organization
    if org.respond_to?(:feature_flags) && !org.feature_flags.include?("product_catalog")
      org.update!(feature_flags: org.feature_flags | ["product_catalog"])
    end
  end
end
