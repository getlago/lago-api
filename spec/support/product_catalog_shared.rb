# frozen_string_literal: true

# Enables the product_catalog flag for every catalog spec, so the files do
# not repeat the setup.
CATALOG_SPEC_PATHS = %r{
  requests/api/v2 |
  graphql/(mutations|resolvers)/.*(product|rate_card|rate_phase|plan_applied|contract)
}x

RSpec.configure do |config|
  config.before do |example|
    # rerun_file_path points at the outermost file even inside shared groups.
    next unless example.metadata[:rerun_file_path].match?(CATALOG_SPEC_PATHS)
    next if example.metadata[:product_catalog] == false
    next unless respond_to?(:organization)

    org = organization
    if org.respond_to?(:feature_flags) && !org.feature_flags.include?("product_catalog")
      org.update!(feature_flags: org.feature_flags | ["product_catalog"])
    end
  end
end
