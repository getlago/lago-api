# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Invoices::ProductCatalog::ProductGroup do
  subject { described_class }

  it do
    expect(subject).to have_field(:product).of_type("Product!")
    expect(subject).to have_field(:amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:fees_count).of_type("Int!")
    expect(subject).to have_field(:filters).of_type("[InvoiceProductCatalogFilterGroup!]!")
  end
end
