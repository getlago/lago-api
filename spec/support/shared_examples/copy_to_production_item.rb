# frozen_string_literal: true

# A Copy to production item type found by id in the sandbox and by code among the kept records of production. Needs `item`,
# `sandbox` and `production`.
RSpec.shared_examples "a copy to production item matched by code" do |factory, **attributes|
  let(:matched_source) { create(factory, organization: sandbox, code: "matched", **attributes) }
  let(:production_twin) { create(factory, organization: production, code: "matched", **attributes) }

  before { production_twin }

  it "finds its source in the sandbox only" do
    expect(item.find_source(matched_source.id)).to eq(matched_source)
    expect(item.find_source(production_twin.id)).to be_nil
  end

  it "finds the kept production record with the source's code" do
    expect(item.find_existing(matched_source)).to eq(production_twin)

    production_twin.discard!
    expect(item.find_existing(matched_source)).to be_nil
  end
end
