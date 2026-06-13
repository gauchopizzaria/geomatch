class PagesController < ApplicationController

  def landing
    redirect_to discover_3d_path if user_signed_in?
    @hide_layout_footer = true
  end

  def terms
  end

  def privacy
  end

  def suporte
  end
end