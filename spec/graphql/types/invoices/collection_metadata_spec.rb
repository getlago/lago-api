# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Invoices::CollectionMetadata do
  subject { described_class }

  it do
    expect(subject.graphql_name).to eq("InvoiceCollectionMetadata")
    expect(subject).to have_field(:current_page).of_type("Int!")
    expect(subject).to have_field(:has_next_page).of_type("Boolean!")
    expect(subject).to have_field(:limit_value).of_type("Int!")
    expect(subject).to have_field(:total_count).of_type("Int!")
    expect(subject).to have_field(:total_count_capped).of_type("Boolean!")
    expect(subject).to have_field(:total_pages).of_type("Int!")
  end
end
