function bhel_5mva_abnormal_conditions()
% BHEL_5MVA_ABNORMAL_CONDITIONS
% MATPOWER model of an oil-immersed transformer under abnormal conditions.
%
% Conditions studied:
% 1. Normal operation
% 2. Overload
% 3. Overvoltage
% 4. Undervoltage
% 5. High temperature
% 6. Low power factor
%
% Based on a 5 MVA, 33/11 kV oil-immersed transformer model.

clc;
close all;

define_constants;

%% Base transformer data
S_rated_MVA   = 5.0;
V_HV_kV       = 33.0;
V_LV_kV       = 11.0;

P_core_kW     = 5.5;      % no-load/core loss
P_cu_full_kW  = 33.0;     % full-load copper loss
Z_percent     = 7.15;     % impedance percent

baseMVA = S_rated_MVA;

%% Derived normal parameters
R_pu_20C = (P_cu_full_kW / 1000) / baseMVA;
Z_pu     = Z_percent / 100;
X_pu     = sqrt(max(Z_pu^2 - R_pu_20C^2, 0));
GS_core_MW = P_core_kW / 1000;

%% Temperature reference
T_ref = 75;    % deg C, reference temperature for load loss
alpha = 0.00393; % copper temperature coefficient

%% Define scenarios
scenarios = struct([]);

scenarios(1).name  = 'Normal';
scenarios(1).load_pu = 1.00;
scenarios(1).pf    = 0.90;
scenarios(1).Vset  = 1.00;
scenarios(1).TempC = 75;

scenarios(2).name  = 'Overload';
scenarios(2).load_pu = 1.30;
scenarios(2).pf    = 0.90;
scenarios(2).Vset  = 1.00;
scenarios(2).TempC = 75;

scenarios(3).name  = 'Overvoltage';
scenarios(3).load_pu = 1.00;
scenarios(3).pf    = 0.90;
scenarios(3).Vset  = 1.08;
scenarios(3).TempC = 75;

scenarios(4).name  = 'Undervoltage';
scenarios(4).load_pu = 1.00;
scenarios(4).pf    = 0.90;
scenarios(4).Vset  = 0.92;
scenarios(4).TempC = 75;

scenarios(5).name  = 'High Temperature';
scenarios(5).load_pu = 1.00;
scenarios(5).pf    = 0.90;
scenarios(5).Vset  = 1.00;
scenarios(5).TempC = 120;

scenarios(6).name  = 'Low Power Factor';
scenarios(6).load_pu = 1.00;
scenarios(6).pf    = 0.70;
scenarios(6).Vset  = 1.00;
scenarios(6).TempC = 75;

n = numel(scenarios);

%% Results arrays
names       = strings(n,1);
load_pu_arr = zeros(n,1);
pf_arr      = zeros(n,1);
Vset_arr    = zeros(n,1);
Temp_arr    = zeros(n,1);

Rpu_arr     = zeros(n,1);
Xpu_arr     = zeros(n,1);
Vsec_arr    = zeros(n,1);
Pout_kW     = zeros(n,1);
Pcore_kW_arr   = zeros(n,1);
Pcopper_kW_arr = zeros(n,1);
Ptotal_kW_arr  = zeros(n,1);
Eff_arr     = zeros(n,1);
Ssend_MVA   = zeros(n,1);

for k = 1:n
    names(k)       = scenarios(k).name;
    load_pu_arr(k) = scenarios(k).load_pu;
    pf_arr(k)      = scenarios(k).pf;
    Vset_arr(k)    = scenarios(k).Vset;
    Temp_arr(k)    = scenarios(k).TempC;

    % Adjust winding resistance for temperature
    R_pu = R_pu_20C * (1 + alpha * (scenarios(k).TempC - T_ref));
    X_pu_use = X_pu;   % assume reactance unchanged

    % Adjust core loss with voltage by MATPOWER GS model
    % GS itself stays constant; actual core loss scales with V^2 through bus voltage

    % Load definition
    Sload_MVA = scenarios(k).load_pu * S_rated_MVA;
    Pload_MW  = Sload_MVA * scenarios(k).pf;
    Qload_MVAr = Sload_MVA * sqrt(max(1 - scenarios(k).pf^2, 0));

    % Create MATPOWER case
    mpc.version = '2';
    mpc.baseMVA = baseMVA;

    mpc.bus = [
        1  3  0         0          GS_core_MW  0  1  scenarios(k).Vset  0  V_HV_kV  1  1.10  0.90;
        2  1  Pload_MW  Qload_MVAr 0           0  1  1.00               0  V_LV_kV  1  1.10  0.90;
    ];

    mpc.gen = [
        1  0  0  100  -100  scenarios(k).Vset  baseMVA  1  100  0
    ];

    mpc.branch = [
        1  2  R_pu  X_pu_use  0  0  0  0  1.0  0  1  -360  360
    ];

    mpopt = mpoption('verbose', 0, 'out.all', 0, 'pf.alg', 'NR');
    results = runpf(mpc, mpopt);

    if ~results.success
        error('Power flow did not converge for scenario: %s', scenarios(k).name);
    end

    % Branch copper loss
    loss_MW = get_losses(results);
    Pcopper_kW_arr(k) = real(loss_MW(1)) * 1000;

    % Core loss from GS and actual primary voltage
    V1 = results.bus(1, VM);
    Pcore_kW_arr(k) = GS_core_MW * V1^2 * 1000;

    % Output power
    Pout_kW(k) = Pload_MW * 1000;

    % Total loss
    Ptotal_kW_arr(k) = Pcopper_kW_arr(k) + Pcore_kW_arr(k);

    % Efficiency
    Eff_arr(k) = 100 * Pout_kW(k) / (Pout_kW(k) + Ptotal_kW_arr(k));

    % Secondary voltage
    Vsec_arr(k) = results.bus(2, VM);

    % Apparent power at sending side
    PF_send = results.branch(1, PF);
    QF_send = results.branch(1, QF);
    Ssend_MVA(k) = sqrt(PF_send^2 + QF_send^2);

    % Save parameters used
    Rpu_arr(k) = R_pu;
    Xpu_arr(k) = X_pu_use;
end

%% Display results
fprintf('\nAbnormal Operating Conditions Analysis\n');
fprintf('-------------------------------------------------------------------------------\n');
fprintf('%-18s %-7s %-6s %-6s %-8s %-9s %-9s %-9s %-9s %-8s\n', ...
    'Scenario','Load','PF','Vset','Temp(C)','Vsec(pu)','Pcore(kW)','Pcu(kW)','Ptot(kW)','Eff(%)');
fprintf('-------------------------------------------------------------------------------\n');

for k = 1:n
    fprintf('%-18s %-7.2f %-6.2f %-6.2f %-8.1f %-9.4f %-9.3f %-9.3f %-9.3f %-8.3f\n', ...
        names(k), load_pu_arr(k), pf_arr(k), Vset_arr(k), Temp_arr(k), ...
        Vsec_arr(k), Pcore_kW_arr(k), Pcopper_kW_arr(k), Ptotal_kW_arr(k), Eff_arr(k));
end

%% Create table
T = table(names, load_pu_arr, pf_arr, Vset_arr, Temp_arr, Rpu_arr, Xpu_arr, ...
    Vsec_arr, Pcore_kW_arr, Pcopper_kW_arr, Ptotal_kW_arr, Pout_kW, Eff_arr, Ssend_MVA, ...
    'VariableNames', {'Scenario','Load_pu','PowerFactor','PrimaryVoltageSet_pu','Temperature_C', ...
    'R_pu','X_pu','SecondaryVoltage_pu','CoreLoss_kW','CopperLoss_kW','TotalLoss_kW', ...
    'OutputPower_kW','Efficiency_percent','SendingEnd_MVA'});

disp(T)

writetable(T, 'abnormal_transformer_conditions_results.csv');
fprintf('\nResults exported to abnormal_transformer_conditions_results.csv\n');

%% Plot 1: losses comparison
figure;
bar(categorical(names), [Pcore_kW_arr Pcopper_kW_arr Ptotal_kW_arr], 'grouped');
grid on;
ylabel('Loss (kW)');
title('Transformer Losses Under Abnormal Operating Conditions');
legend('Core loss','Copper loss','Total loss','Location','northwest');

%% Plot 2: efficiency comparison
figure;
bar(categorical(names), Eff_arr);
grid on;
ylabel('Efficiency (%)');
title('Transformer Efficiency Under Abnormal Operating Conditions');

%% Plot 3: secondary voltage comparison
figure;
bar(categorical(names), Vsec_arr);
grid on;
ylabel('Secondary Voltage (p.u.)');
title('Secondary Voltage Under Abnormal Operating Conditions');

%% Plot 4: parameter comparison
figure;
yyaxis left
bar(categorical(names), Rpu_arr);
ylabel('R_{pu}');
yyaxis right
plot(categorical(names), Xpu_arr, '-o', 'LineWidth', 1.5);
ylabel('X_{pu}');
title('Equivalent Transformer Parameters Under Each Scenario');
grid on;

end