# frozen_string_literal: true

# The seeds create users with a password that is public in this repository.
# They must never create those users on a shared environment. Outside
# development and test, the operator must supply a password through
# LAGO_SEED_USER_PASSWORD.
if !Rails.env.local? && ENV["LAGO_SEED_USER_PASSWORD"].blank?
  abort(<<~MESSAGE)
    db:seed is disabled in the #{Rails.env} environment.

    The seeded users use a default password that is public in the lago-api
    repository. To seed a shared environment, set LAGO_SEED_USER_PASSWORD to a
    secret value first.
  MESSAGE
end

Dir[Rails.root.join("db/seeds/*.rb")].sort.each do |seed|
  load seed
end
