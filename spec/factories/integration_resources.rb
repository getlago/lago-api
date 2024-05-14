FactoryBot.define do
  factory :integration_resource do
    association :syncable, factory: %i[invoice payment credit_note].sample
    external_id { SecureRandom.uuid }
  end
end
