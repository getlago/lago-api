# frozen_string_literal: true

# Recap of what was seeded. API keys are generated for organizations configured
# through LAGO_SEED_ORGS, so this is the only place they are shown.
def print_seeded_organization(organization)
  api_key = organization.api_keys.non_expiring.first
  puts "  #{organization.name} — id: #{organization.id} — api key: #{api_key&.value}"
end

puts "\nSeeded organizations:"
SeedOrganizations.each { |organization| print_seeded_organization(organization) }

catalog_config = SeedOrganizations.product_catalog_config
print_seeded_organization(SeedOrganizations.find!(catalog_config)) if catalog_config
puts
