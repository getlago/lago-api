# frozen_string_literal: true

# Shared contract for a mail whose template renders the `layouts/lago_logo` partial.
# The host group must define `mail` as the message under test.
RSpec.shared_examples "a mail with the Lago logo header" do
  it "renders the Lago logo header once" do
    logos = Nokogiri::HTML(mail.body.encoded).css("svg[viewbox='0 0 80 24']")

    expect(logos.map { it.parent["style"] }).to eq(["margin-bottom: 32px;width: 80px;height: 24px;"])
  end
end
