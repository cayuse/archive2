class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin, except: [:show, :edit, :update]
  before_action :set_user, only: [:show, :edit, :update, :destroy]

  def index
    @users = policy_scope(User).order(:name)
  end

  def show
    authorize @user
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
    authorize @user
  end

  def update
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

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: "Admin access required."
    end
  end
end
