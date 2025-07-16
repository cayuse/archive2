class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin, only: [:index, :new, :create, :destroy]
  before_action :require_admin_for_password_actions, only: [:reset_password, :set_password]
  before_action :set_user, only: [:show, :edit, :update, :destroy, :reset_password, :set_password]

  def index
    @users = policy_scope(User).order(:name)
  end

  def show
    authorize @user
    
    # If user is viewing their own profile, redirect to profile path
    if current_user == @user
      redirect_to profile_path
      return
    end
    
    # Only admins can view other users' profiles
    unless current_user.admin?
      redirect_to root_path, alert: "You can only view your own profile."
      return
    end
  end

  def new
    @user = User.new
    authorize @user
  end

  def create
    @user = User.new(user_params)
    authorize @user
    
    # Generate a temporary password
    temporary_password = SecureRandom.alphanumeric(12)
    @user.password = temporary_password
    @user.password_confirmation = temporary_password
    
    if @user.save
      # Send welcome email
      UserMailer.welcome_email(@user, temporary_password).deliver_now
      
      redirect_to users_path, notice: "User #{@user.name} was successfully created and welcome email sent."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Only admins can edit users
    unless current_user.admin?
      redirect_to root_path, alert: "Admin access required to edit users."
      return
    end
    authorize @user
  end

  def update
    # Only admins can update users
    unless current_user.admin?
      redirect_to root_path, alert: "Admin access required to update users."
      return
    end
    authorize @user
    if @user.update(user_params)
      redirect_to @user, notice: 'User was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @user
    @user.destroy
    redirect_to users_path, notice: 'User was successfully deleted.'
  end

  # Admin-only: Reset user password and send welcome email
  def reset_password
    authorize @user, :manage_password?
    
    # Log the password reset action for security auditing
    Rails.logger.info "ADMIN PASSWORD RESET: Admin #{current_user.email} reset password for user #{@user.email} at #{Time.current}"
    
    # Generate a new temporary password
    new_password = SecureRandom.alphanumeric(12)
    @user.password = new_password
    @user.password_confirmation = new_password
    
    if @user.save
      # Send welcome email with new password
      UserMailer.welcome_email(@user, new_password).deliver_now
      
      redirect_to edit_user_path(@user), notice: "Password reset for #{@user.name}. Welcome email sent with new temporary password."
    else
      redirect_to edit_user_path(@user), alert: "Failed to reset password: #{@user.errors.full_messages.join(', ')}"
    end
  end

  # Admin-only: Set a specific password for user
  def set_password
    authorize @user, :manage_password?
    
    # Handle parameters safely
    user_params = params[:user]
    if user_params.nil?
      redirect_to edit_user_path(@user), alert: "No password parameters received."
      return
    end
    
    password = user_params[:password]
    password_confirmation = user_params[:password_confirmation]
    
    # Log the password set action for security auditing
    Rails.logger.info "ADMIN PASSWORD SET: Admin #{current_user.email} set password for user #{@user.email} at #{Time.current}"
    
    if password.blank?
      redirect_to edit_user_path(@user), alert: "Password cannot be blank."
      return
    end
    
    if password != password_confirmation
      redirect_to edit_user_path(@user), alert: "Password confirmation doesn't match."
      return
    end
    
    if password.length < 6
      redirect_to edit_user_path(@user), alert: "Password must be at least 6 characters long."
      return
    end
    
    @user.password = password
    @user.password_confirmation = password_confirmation
    
    if @user.save
      redirect_to edit_user_path(@user), notice: "Password for #{@user.name} has been updated successfully."
    else
      redirect_to edit_user_path(@user), alert: "Failed to update password: #{@user.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_user
    @user = User.find_by!(id: params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: "Admin access required."
    end
  end

  def require_admin_for_password_actions
    unless current_user&.admin?
      redirect_to root_path, alert: "Admin access required for password management."
    end
  end
end
