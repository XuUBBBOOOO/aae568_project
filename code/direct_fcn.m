function [alpha, alpha_t, tf, sol] = direct_fcn(Chaser,...
    Target, Nav, t0, plot_opt, tf_rel_guess)

yinit = [Nav.r; Nav.theta; Nav.rdot; Nav.thetadot];
slack_guess = sqrt(tf_rel_guess);
ICsolver0 = [tf_rel_guess];

options = optimset('Algorithm','sqp','display','off');
options.Nodes = 300;

T = linspace(0, 1, options.Nodes);
solinit0 = bvpinit(T, yinit', ICsolver0);
solinit0.consts.Chaser = Chaser;
solinit0.consts.Target = Target;
solinit0.consts.Nav = Nav;
solinit0.consts.t0 = t0;
solinit0.control(1,:) = 0*linspace(0, 0, options.Nodes);

[T,X] = ode113(@(t,X)(direct_eoms(t, X, 0, solinit0.parameters, solinit0.consts)), T, yinit);

% solinit0.y(1,:) = X(:,1)';
% solinit0.y(2,:) = X(:,2)';
% solinit0.y(3,:) = X(:,3)';
% solinit0.y(4,:) = X(:,4)';

solinit0.y(1,:) = linspace(Nav.r, Target.r0, options.Nodes);
solinit0.y(2,:) = linspace(Nav.theta, Target.thetadot0*(tf_rel_guess+t0) - Target.theta0, options.Nodes);
solinit0.y(3,:) = linspace(Nav.rdot, Target.rdot0, options.Nodes);
solinit0.y(4,:) = linspace(Nav.thetadot, Target.thetadot0, options.Nodes);

options.cost = @direct_cost;

options.isdirect = 1;

tic;
sol = bvpmc(@direct_eoms, [], @direct_bcs, solinit0, options);
time0 = toc;

alpha = sol.control;
alpha_t = linspace(0,1,options.Nodes);
tf = sol.parameters(1);
