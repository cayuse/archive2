class ProfileController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

  def show
    # Profile show page - could display user stats, activity, etc.
    redirect_to edit_profile_path
  end

  def edit
    # Edit profile form
  end

  def update
    if @user.update(user_params)
      redirect_to edit_profile_path, notice: 'Profile updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = current_user
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end 