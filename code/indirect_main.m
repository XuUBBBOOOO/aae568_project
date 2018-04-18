% Collin York
% Initialize Indirect Optimization
clear all; clc; close all;
colors = lines(5);

% Options to Plot Indirect Optimization
plot_opt.indirect = 1;      % 1=plot, 0=no plot
plot_opt.i = 0;             % last plot figure number
plot_opt.actual = true;

% Options for simulation
sim_opt.optim = 'indirect';     % which optimization method to use
sim_opt.estim = 'ekf';          % which estimate method to use
sim_opt.stateTol = 1e-6;        % tolerance to check if state has reached final value

%% Define Dimensional Initial Conditions
charL = 6378 + 200;     % characteristic length, km; TODO - DEFINE THIS
charT = 1;              % characteristic time, sec; TODO - DEFINE THIS
charM = 500;            % characteristic mass, kg; TODO - DEFINE THIS
muEarth = 3.986e5;      % Earth gravity parameter, km^3/s^2

% Dimensional initial conditions
T = 1;                  % Thrust, Newtons; TODO - DEFINE THIS
Isp = 1500;             % Specific impulse, sec
g0 = 9.80665/1000;      % Mean Earth gravity, km/s^2

r0 = 7000;              % Initial orbital radius of chaser, km
theta0 = 0;             % Initial longigutde of chaser, rad
rdot0 = 0;              % Initial radial velocity of chaser, km/s

% Compute thetadot for a circular orbit; rad/s
thetadot0 = sqrt(muEarth/r0^3);

% Chaser Nondimensional Parameters
% These will be fed in by main code
Chaser.T = 0.05;        % Non-dim thrust (Value tends to work well)
Chaser.mdot = 0.001;    % Non-dim mdot (Value tends to work well)
Chaser.m0 = 1;          % Non-dim mass; starts at 1; not state variable
Chaser.ts_opt = 1;      % Non-dim time-of-flight for one "leg" between observations 

% Actual Initial State for Optimizer at t0
Actual.X = [1; 0; 0; 1];    %Current state [r, theta, rdot, thetadot]
Actual.X_history = {};      % Each cell holds the state history for one segment
Actual.t_history = {};      % Each cell holds the time associated with the state history
Actual.alpha_history = {};
Actual.alpha_t_history = {};

% Filtered Nav Initial State for Optimizer at t0
Nav.r = 1;
Nav.theta = 0;
Nav.rdot = 0;
Nav.thetadot = 1;
Nav.P0 = zeros(4); % Initial Covariance to test EKF
Nav.X_history = {};
Nav.t_history = {};

% Target Actual State at t = 0 (note: not same as updated t0)
Target.r0 = 1.01;
Target.theta0 = 0.21;
Target.rdot0 = 0;
Target.thetadot0 = sqrt(1/Target.r0^3);

% Noise Covariance
Cov.R = eye(4)*1e-4; % Acceleration Process Noise (xdot = f(x,u,t) + C*w)
Cov.Z = eye(4)*1e-4; % Measurement noise (y = x + z)

t_now = 0;          % t_now is the current reoptimization time (not always 0)
tf_rel_guess = pi;  % pi is good guess when t_now = 0, will update as tf-t_now

% helpful IC, replaced by lambda_f when re-optimizing
lambda0_guess = [22; -7; 20; -5];

if(plot_opt.actual)
    plot_opt.i = plot_opt.i + 1;
    h_traj = figure(plot_opt.i);
    hold on;
    ax_traj = gca;
    title('Trajectory');
    xlabel('x, nondim');
    ylabel('y, nondim');
    set(ax_traj, 'fontsize', 12);
    
    plot_opt.i = plot_opt.i + 1;
    h_state = figure(plot_opt.i);
    subplot(4,1,1); hold on;
    ax_r = gca;
    title('State Histories');
    ylabel('r, nd');
    set(ax_r, 'fontsize', 12);
    
    subplot(4,1,2); hold on;
    ax_theta = gca;
    ylabel('\theta, rad');
    set(ax_theta, 'fontsize', 12);
    
    subplot(4,1,3); hold on;
    ax_rdot = gca;
    ylabel('$$\dot{r}$$, nd', 'interpreter', 'latex');
    set(ax_rdot, 'fontsize', 12);
    
    subplot(4,1,4); hold on;
    ax_thetadot = gca;
    ylabel('$$\dot{\theta}$$, nd', 'interpreter', 'latex');
    xlabel('Time, nd');
    set(ax_thetadot, 'fontsize', 12);
end
% Begin Mission Loop
gameover = false;
count = 0;
while(~gameover)
    %% Using current state est., compute optimal traj. to reach target
    %   
    %   Optimization method should spit out the FULL optimal control
    %   from the current state to the final rendezvous
    %
    %   We won't necessarily use the entire optimal solution, just a
    %   section of it that corresponds to our flight time between
    %   observations
    switch(lower(sim_opt.optim))
        case 'indirect'
            % Indirect Optimization - Collin
            % Outputs: 
            % - alpha: Control history for the entire optimal trajectory
            % - alpha_t: times associated with alpha
            % - tf: final time on the optimal trajectory, relative to
            % mission start
            % - t_seg: time at the end of "the segment", relative to
            % mission start
            % - lambda_seg: costate values at the end of "the segment", 
            %   i.e., part way through the optimal trajectory.
            if(count > 0)
                lambda0_guess = lambda_seg;         % Update
                t_now = t_now + t_seg;              % Update starting time
                tf_rel_guess = tf - t_now ;         % Update TOF guess
            end
            [alpha, alpha_t, tf, t_seg, lambda_seg] = indirect_fcn(Chaser,...
                Target, Nav, t_now, plot_opt, lambda0_guess, tf_rel_guess);
            
            fprintf('Computed optimal control for t = %f to %f\n', ...
                t_now, t_seg);
    end
    
    
    %% Propagate for one "step" until next observation
    
    % Propagate the true state with interpolated process noise
    Actual = prop_actual(Actual, Chaser, Cov, alpha, alpha_t, t_now, t_seg);
    
    switch(lower(sim_opt.estim))
        case 'ekf'
            % EKF function to propagate State covariance in P in continuous
            % time with acceleration process covariance
            Nav = prop_EKF(Nav, Chaser, Cov, alpha, alpha_t, t_now, t_seg);
    end
    
    %% Make Observation
    %   
    %   * Update state estimate
    %   * Update covariance
    
    switch(lower(sim_opt.estim))
        case 'ekf'
            H = eye(4);         % TODO - what is this?
            G = eye(4);         % TODO - what is this?
            L_k = (Nav.P * H.') / (H*Nav.P*H.' + G*Cov.Z*G.');
            y = H*Actual.X + Cov.Z*randn(4,1);  % measurement + noise
            % apriori nav estimate
            nav_pre = [Nav.r; Nav.theta; Nav.rdot; Nav.thetadot];
            % nav estimate post observation
            nav_post = nav_pre + L_k*(y - H*nav_pre);   % update
            
            % Update Nav state after observation
            Nav.r = nav_post(1);
            Nav.theta = nav_post(2);
            Nav.rdot = nav_post(3);
            Nav.thetadot = nav_post(4);
            Nav.P = (eye(4) - L_k*H)*Nav.P;     % covariance update
    end
    
    if(plot_opt.actual)
        % Plot Actual path (where we actually are)
        x = Actual.X_history{end}(:,1).*cos(Actual.X_history{end}(:,2));
        y = Actual.X_history{end}(:,1).*sin(Actual.X_history{end}(:,2));
        h_true = plot(ax_traj, x, y, 'linewidth', 2, 'color', colors(1,:));
        
        % Plot Nav solution (where we think we are)
        x = Nav.X_history{end}(:,1).*cos(Nav.X_history{end}(:,2));
        y = Nav.X_history{end}(:,1).*sin(Nav.X_history{end}(:,2));
        h_nav = plot(ax_traj, x, y, 'linewidth', 2, 'color', colors(2,:));
        
        if(count == 0)
            grid(ax_traj, 'on');
            axis(ax_traj, 'equal');
            legend([h_true, h_nav], 'Actual', 'Nav');
        end
        
        plot(ax_r, Actual.t_history{end}, Actual.X_history{end}(:,1),...
            'linewidth', 2, 'color', colors(1,:));
        plot(ax_theta, Actual.t_history{end}, Actual.X_history{end}(:,2),...
            'linewidth', 2, 'color', colors(1,:));
        plot(ax_rdot, Actual.t_history{end}, Actual.X_history{end}(:,3),...
            'linewidth', 2, 'color', colors(1,:));
        plot(ax_thetadot, Actual.t_history{end}, Actual.X_history{end}(:,4),...
            'linewidth', 2, 'color', colors(1,:));
        
        plot(ax_r, Nav.t_history{end}, Nav.X_history{end}(:,1),...
            'linewidth', 2, 'color', colors(2,:));
        plot(ax_theta, Nav.t_history{end}, Nav.X_history{end}(:,2),...
            'linewidth', 2, 'color', colors(2,:));
        plot(ax_rdot, Nav.t_history{end}, Nav.X_history{end}(:,3),...
            'linewidth', 2, 'color', colors(2,:));
        plot(ax_thetadot, Nav.t_history{end}, Nav.X_history{end}(:,4),...
            'linewidth', 2, 'color', colors(2,:));
        
        plot(ax_r, [t_now, t_seg], Target.r0*[1,1], 'k--', 'linewidth', 2);
        plot(ax_theta, [t_now, t_seg], Target.theta0*[1,1], 'k--', 'linewidth', 2);
        plot(ax_rdot, [t_now, t_seg], Target.rdot0*[1,1], 'k--', 'linewidth', 2);
        plot(ax_thetadot, [t_now, t_seg], Target.thetadot0*[1,1], 'k--', 'linewidth', 2);
    end
    
    %% Evaluate status
    %   Has spacecraft reached the target?
    
    X_targ = getTargetState(Target, tf);
    X_chaser = [Nav.r; Nav.theta; Nav.rdot; Nav.thetadot];
    state_err = norm(X_targ - X_chaser);
    gameover = state_err < sim_opt.stateTol;
    
    if(~gameover)
        % Update Chaser state
        Chaser.m0 = Chaser.m0 - Chaser.mdot*(tf - t_now);
    end
    
    count = count + 1;
end