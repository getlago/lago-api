# frozen_string_literal: true

# This matcher allows to match an HTML snapshot with the same logic as the `match_snapshot` matcher.
#
# The main difference is that it will add the test context and a `.html` extension to the snapshot name. For instance, if the test is:
#
# ```ruby
# context "when the customer is a company" do
#   let(:customer) { create(:customer, :company) }
#
#   it "renders the invoice" do
#     expect(rendered_template).to match_html_snapshot
#   end
# end
# ```
#
# The snapshot name will be `when_the_customer_is_a_company/renders_the_invoice.html.snap`.
#
# Usage example:
#
# ```
# it "renders the invoice" do
#   expect(rendered_template).to match_html_snapshot
# end
# ```
RSpec::Matchers.define :match_html_snapshot do |name = nil|
  match(notify_expectation_failures: true) do |html|
    name = [snapshot_name(RSpec.current_example.metadata), name].compact.join("/")
    name += ".html"
    html = beautify(html)
    expect(html).to match_snapshot(name)
  end

  private

  def snapshot_name(metadata)
    description = metadata[:description].empty? ? metadata[:scoped_id] : metadata[:description]
    example_group = metadata.key?(:example_group) ? metadata[:example_group] : metadata[:parent_example_group]

    description = description.tr("/", "_").tr(" ", "_")
    if example_group
      [snapshot_name(example_group), description].join("/")
    else
      description
    end
  end

  def beautify(html)
    # Ensure the HTML string is properly encoded as UTF-8, otherwise we won't be able to write the snapshot
    html = html.force_encoding("UTF-8") if html.encoding != Encoding::UTF_8
    HtmlBeautifier.beautify(html, stop_on_errors: true)
  end
end
