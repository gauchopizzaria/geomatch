class Discover3dController < ApplicationController
  before_action :authenticate_user!

  GALLERY_LIMIT = 60

  def gallery
    base = User.visible
               .where.not(id: current_user.excluded_user_ids + [current_user.id])

    @filters = {
      sexo:   params[:sexo].presence,
      estado: params[:estado].presence,
      cidade: params[:cidade].presence
    }

    scope = base
    scope = scope.where("LOWER(gender) = ?", @filters[:sexo].downcase) if @filters[:sexo]
    scope = scope.where(state: @filters[:estado])                       if @filters[:estado]
    scope = scope.where(city: @filters[:cidade])                        if @filters[:cidade]

    if @filters.values.all?(&:blank?)
      # Sem filtros: perfis em destaque (verificados → premium → mais ativos)
      free_plan_id = Plan.find_by(name: "Free")&.id
      scope = scope.order(verified: :desc)
      scope = scope.order(Arel.sql("CASE WHEN plan_id = #{free_plan_id.to_i} THEN 1 ELSE 0 END")) if free_plan_id
      scope = scope.order(Arel.sql("last_seen_at DESC NULLS LAST"))
    else
      scope = scope.order(Arel.sql("last_seen_at DESC NULLS LAST"))
    end

    @users = scope.limit(GALLERY_LIMIT)

    @available_states = base.where.not(state: [nil, ""]).distinct.pluck(:state).sort
    @available_cities = if @filters[:estado]
                          base.where(state: @filters[:estado])
                              .where.not(city: [nil, ""])
                              .distinct.pluck(:city).sort
                        else
                          []
                        end
  end
end
