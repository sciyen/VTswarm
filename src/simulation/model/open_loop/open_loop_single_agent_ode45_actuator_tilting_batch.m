close all;

%% Simulation parameters
T = 1;
angles = [2.5 5 7.5 10];

%% Command generation
for idx=1:length(angles)
    % Initial conditions
    y0 = zeros([18 1]);
    y0(4:12) = reshape(eye(3), [9 1]);
    
    % Solver
    options = odeset('RelTol',1e-7,'AbsTol',1e-9);
    [t, y] = ode45(@(t,y) drone_fly(t, y, angles(idx)), [0 T], y0, options);
    
    dydt = zeros([length(y) 18]);
    inputs = zeros([length(y) 2]);
    outputs = zeros([length(y) 12]);
    for i=1:length(y)
        [dydt(i, :), inputs(i, :), outputs(i, :)] = drone_fly(t(i), y(i, :)', angles(idx));
    end
    plot_single(t, r, dydt, y, inputs, outputs, idx-1, length(angles));

end


%% Plot
r = 1:10:length(y);
%plotter(t, r, dydt, y, inputs, outputs);

%% Functions
function [dydt, inputs, outputs] = drone_fly(t, y, ext)
    %% Parameters
    [key, params] = get_params();
    g = params('g');     % gravity
    rho = params('rho');   % kg/m3
    prop_d = params('prop_d'); % 8 inch = 20.3 cm

    CT_u = params('CT_u'); % upper propeller thrust coefficient
    CT_l = params('CT_l'); % lower propeller thrust coefficient
    CP_u = params('CP_u');   % upper propeller drag coefficient
    CP_l = params('CP_l');   % lower propeller drag coefficient
    
    % Drone
    m_a = params('m_a');     % Mass, Kg
    m_fm = params('m_fm');
    r_pg = params('r_pg');  % Leverage length from c.p. to c.g.
    r_fm = params('r_fm'); % Leverage length from c.fm. to c.g. 

    I_fm = params('I_fm'); % Body Inertial
    I_a  = params('I_a'); % Actuator Inertial

    %% State variables
    W = y(1:3);
    Q = reshape(y(4:12), [3 3]); % 3x3
    dP = y(13:15);
    P = y(16:18);

    %% Control input
    % Thrust command
    w_prop_u = 198.2746; % Upper rotor speed
    w_prop_l = 198.2746; % Lower rotor speed

    % Gimbal command
    w0 = pi/2;
    amp = 10 * pi / 180;
    w_a = 0;

    xi = ext*pi/180;
    d_xi = 0*t;
    dd_xi = 0*t;
    
    eta = 0;
    d_eta = 0*t;
    dd_eta = 0*t;

    %% System start
    % Translational thrust
    T_f = rho * w_prop_u^2 * prop_d^4 * CT_u + rho * w_prop_l^2 * prop_d^4 * CT_l;

    % Drag torque
    T_d = rho * w_prop_u^2 * prop_d^5 * CP_u - rho * w_prop_l^2 * prop_d^5 * CP_l;

    % Gyroscopic moment
    A_w_a = [0; 0; w_a];
    
    A1_M_m = I_a * [dd_eta; 0; 0] + cross([d_eta; 0; 0], I_a * A_w_a);
    A1_H_m = Rx(eta) * (I_a * A_w_a);
    A1_I_a = Rx(eta) * I_a;
    
    %B_M_m = Ry(xi)' * A1_M_m + A1_I_a * [0; dd_xi; 0] + cross([0; d_xi; 0], A1_H_m);
    B_M_m = Rx(eta) * I_a * [0; dd_xi; 0] + Ry(xi) * I_a * [dd_eta; 0; 0];
    B_H_m = Ry(xi) * A1_H_m;
    B_I_a = Ry(xi) * A1_I_a;

    B_R_A = Ry(xi) * Rx(eta);

    % Thrust torque
    thrust = B_R_A * [0; 0; T_f];
    B_M_f = cross(r_pg, thrust);

    % Drag torque from motor
    B_M_d = B_R_A * [0; 0; T_d];

    % Variable Inertia
    I_b = B_I_a + m_a * [r_pg(3).^2 0 0; 0 r_pg(3).^2 0; 0 0 0] + I_fm + m_fm * [r_fm(3).^2 0 0; 0 r_fm(3).^2 0; 0 0 0];

    %% Newton-Euler equation
    B_M = -cross(W, I_b * W) + B_M_f - B_M_d - B_M_m;

    dW = I_b \ B_M;
    dQ = reshape(Q * skew(W), [9 1]);
    
    I_thrust = Q * thrust/(m_a + m_fm);
    ddP = [0; 0; -g] + I_thrust ;
    dydt = [dW; dQ; ddP; dP];
    inputs = [dd_xi dd_eta];
    outputs = [I_thrust ; B_M_f; - B_M_d; - B_M_m];
end

function r = Rx(t)
    r = [1 0      0;
         0 cos(t) -sin(t);
         0 sin(t) cos(t)];
end

function r = Ry(t)
    r = [cos(t)  0 sin(t);
         0       1 0; 
         -sin(t) 0 cos(t)];
end

function X = skew(x)
    X=[0 -x(3) x(2) ; x(3) 0 -x(1) ; -x(2) x(1) 0 ];
end


function plot_single(t, r, dydt, y, inputs, outputs, idx, len)
%% Extract parameters
    [key, params] = get_params();
    r_pg = params('r_pg');  % Leverage length from c.p. to c.g.
    r_fm = params('r_fm');  % Leverage length from c.fm. to c.g. 
    dd_xi = inputs(:, 1);
    dd_eta = inputs(:, 2);
    thrust = outputs(:, 1:3);
    B_M_f = outputs(:, 4:6);
    B_M_d = outputs(:, 7:9);
    B_M_m = outputs(:, 10:12);

    % Rotational
    % Angular velocity
    dW = dydt(:, 1:3);
    W = y(:, 1:3);
    % Orientation
    Q = reshape(y(:, 4:12), [length(y) 3 3]); % 3x3
    % Euler angles
    QT = permute(Q, [2 3 1]);
    eulZYX = rotm2eul(QT,'ZYX');
    
    % Translational
    ddP = dydt(:, 13:15);
    dP = y(:, 13:15);
    P = y(:, 16:18);

    CoP = P(:, 1:3) + squeeze(pagemtimes(permute(Q, [2 3 1]), r_pg))';

%% Draw position and orientation
    %figure('Position', [10 10 800 800])
    f=figure(1);
    f.Position = [100 100 1200 800];
    Ax = subplot(4, len, 1 + 4*idx);
    plot(t, eulZYX(:, 1),'DisplayName','Yaw','LineWidth',2); hold on 
    plot(t, eulZYX(:, 2),'DisplayName','Pitch','LineWidth',2); hold on 
    plot(t, eulZYX(:, 3),'DisplayName','Roll','LineWidth',2); hold on 
    ylabel('rad')
    if (idx==3)
        xlabel('time')
    end
    if (idx==0)
        title('Orientation')
    end
    hl = legend('show');
    set(hl, 'Interpreter','latex')
    
    %% Draw velocity
    %figure('Position', [10 10 800 400])
    Ax = subplot(4, len, 2 + 4*idx);
    plot(t, W(:, 3),'DisplayName','Yaw $$\psi$$','LineWidth',2); hold on 
    plot(t, W(:, 2),'DisplayName','Pitch $$\theta$$','LineWidth',2); hold on 
    plot(t, W(:, 1),'DisplayName','Roll $$\phi$$','LineWidth',2); hold on 
    ylabel('rad')
    if (idx==3)
        xlabel('time')
    end
    if (idx==0)
        title('Angular velocity w.r.t. body frame')
    end
    hl = legend('show');
    set(hl, 'Interpreter','latex')
    
    Ax = subplot(4, len, 3 + 4*idx);
    plot(t, P(:, 1),'DisplayName','X','LineWidth',2); hold on 
    plot(t, P(:, 2),'DisplayName','Y','LineWidth',2); hold on 
    plot(t, P(:, 3),'DisplayName','Z','LineWidth',2); hold on 
    ylabel('m')
    if (idx==3)
        xlabel('time')
    end
    if (idx==0)
        title('Position')
    end
    hl = legend('show');
    set(hl, 'Interpreter','latex')
    
    Ax = subplot(4, len, 4 + 4*idx);
    plot(t, dP(:, 1),'DisplayName','X','LineWidth',2); hold on 
    plot(t, dP(:, 2),'DisplayName','Y','LineWidth',2); hold on 
    plot(t, dP(:, 3),'DisplayName','Z','LineWidth',2); hold on 
    ylabel('m/s')
    if (idx==3)
        xlabel('time')
    end
    if (idx==0)
    title('Velocity w.r.t. inertial frame')
    end
    hl = legend('show');
    set(hl, 'Interpreter','latex')
end