# frozen_string_literal: true

class AddOnsQuery < BaseQuery
  def call(search_term:, page:, limit:, filters: {})
    @search_term = search_term

    add_ons = base_scope.result
    add_ons = add_ons.where(id: filters[:ids]) if filters[:ids].present?
    add_ons = add_ons.order(created_at: :desc).page(page).per(limit)

    result.add_ons = add_ons
    result
  end

  private

  attr_reader :search_term

  def base_scope
    AddOn.where(organization:).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end
end
