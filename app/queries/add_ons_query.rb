# frozen_string_literal: true

class AddOnsQuery < BaseQuery
  def call
    add_ons = base_scope.result
    add_ons = paginate(add_ons)
    add_ons = add_ons.order(created_at: :desc)

    result.add_ons = add_ons
    result
  end

  private

  def base_scope
    AddOn.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: 'or',
      name_cont: search_term,
      code_cont: search_term
    }
  end
end
