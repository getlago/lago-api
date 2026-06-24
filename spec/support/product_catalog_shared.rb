# frozen_string_literal: true

# The catalog surface is gated on the organization's product_catalog feature
# flag on both APIs; enable it transparently for every catalog spec so each
# file does not have to repeat the flag setup.
CATALOG_SPEC_PATHS = %r{
  requests/api/v2 |
  graphql/(mutations|resolvers)/.*(product|rate_card|plan_applied)
}x

RSpec.configure do |config|
  config.before do |example|
    # rerun_file_path points at the outermost spec file even for examples
    # defined inside shared example groups.
    next unless example.metadata[:rerun_file_path].match?(CATALOG_SPEC_PATHS)
    next if example.metadata[:product_catalog] == false
    next unless respond_to?(:organization)

    org = organization
    if org.respond_to?(:feature_flags) && !org.feature_flags.include?("product_catalog")
      org.update!(feature_flags: org.feature_flags | ["product_catalog"])
    end
  end
end
