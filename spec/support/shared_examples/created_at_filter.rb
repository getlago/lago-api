# frozen_string_literal: true

# Filter of a native v2 list on `created_at_from` and `created_at_to`. The including group
# provides:
# - `organization`
# - `filtered_path`: the list path
# - `create_filtered_record`: a lambda creating one listed record at the given `created_at`
#
# Rows already listed by the including group are tolerated: they are not created at the
# second the examples filter on.
RSpec.shared_examples "a v2 list filtered on created_at" do |collection:|
  let(:created_at_bound) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  let(:rows_around_bound) do
    [-1, 0, 1].map { |offset| create_filtered_record.call(created_at_bound + offset.seconds) }
  end

  before { rows_around_bound }

  it "returns the rows created between created_at_from and created_at_to, both included" do
    get_with_token(organization, filtered_path, created_at_from: created_at_bound.iso8601(6), created_at_to: created_at_bound.iso8601(6))

    expect(response).to have_http_status(:ok)
    expect(json[collection].map { it[:lago_id] }).to eq([rows_around_bound.second.id])
  end

  it "covers the whole day of a date-only bound" do
    day = created_at_bound.to_date.iso8601
    get_with_token(organization, filtered_path, created_at_from: day, created_at_to: day)

    expect(response).to have_http_status(:ok)
    expect(json[collection].map { it[:lago_id] }).to match_array(rows_around_bound.map(&:id))
  end

  it "rejects a bound that is not a datetime" do
    get_with_token(organization, filtered_path, created_at_from: "2026-13-01")

    expect(response).to have_http_status(:unprocessable_content)
    expect(json).to eq(
      status: 422,
      error: "Unprocessable Entity",
      code: "validation_errors",
      error_details: {created_at_from: ["invalid_date"]}
    )
  end

  it "rejects a bound that is not a string, rather than ignoring it" do
    get_with_token(organization, filtered_path, created_at_to: {lte: created_at_bound.iso8601(6)})

    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq(created_at_to: ["invalid_date"])
  end
end
