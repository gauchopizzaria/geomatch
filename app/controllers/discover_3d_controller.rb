class Discover3dController < ApplicationController
  before_action :authenticate_user!

  GALLERY_LIMIT = 60

  def gallery
    base = User.visible
               .where.not(id: current_user.excluded_user_ids + [current_user.id])

    @filters = {
      sexo:  params[:sexo].presence,
      state: params[:state].presence,
      city:  params[:city].presence
    }

    scope = base
    scope = scope.where("LOWER(gender) = ?", @filters[:sexo].downcase) if @filters[:sexo]
    scope = scope.where("state ILIKE ?", @filters[:state].strip)       if @filters[:state]
    scope = scope.where("city ILIKE ?", @filters[:city].strip)         if @filters[:city]

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

    @favorites_map = current_user.favorites
                                  .where(favorited_user_id: @users.map(&:id))
                                  .each_with_object({}) { |f, h| h[f.favorited_user_id] = f.id }

  end
end
