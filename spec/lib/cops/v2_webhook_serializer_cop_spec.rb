# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::V2WebhookSerializerCop, :config do
  it "registers an offense for a v2 serializer built without webhook: true" do
    expect_offense(<<~RUBY)
      ::V2::ProductSerializer.new(object, root_name: object_type)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Build a v2 webhook body with `webhook: true`, which embeds the expansions declared for webhooks.
    RUBY
  end

  it "registers an offense for a namespaced v2 serializer without options" do
    expect_offense(<<~RUBY)
      V2::Invoices::PaymentDisputeLostSerializer.new(object)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Build a v2 webhook body with `webhook: true`, which embeds the expansions declared for webhooks.
    RUBY
  end

  it "registers an offense for webhook: false" do
    expect_offense(<<~RUBY)
      ::V2::RateCardSerializer.new(object, root_name: object_type, webhook: false)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Build a v2 webhook body with `webhook: true`, which embeds the expansions declared for webhooks.
    RUBY
  end

  it "does not register an offense for a v2 serializer built with webhook: true" do
    expect_no_offenses(<<~RUBY)
      ::V2::ProductSerializer.new(object, root_name: object_type, webhook: true)
    RUBY
  end

  it "does not register an offense when webhook: true comes before other options" do
    expect_no_offenses(<<~RUBY)
      ::V2::CatalogPlanSerializer.new(object, root_name: "plan", webhook: true, includes: %i[counts])
    RUBY
  end

  it "does not register an offense for a v1 serializer" do
    expect_no_offenses(<<~RUBY)
      ::V1::PlanSerializer.new(object, root_name: "plan", includes: %i[charges])
    RUBY
  end
end
