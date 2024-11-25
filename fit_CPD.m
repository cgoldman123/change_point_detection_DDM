function [fit_results, DCM] = fit_CPD(root, subject_id, DCM)

    data_dir = [root '\NPC\Analysis\T1000\data-organized\' subject_id '\T0\behavioral_session\']; % always in T0?

    has_practice_effects = false;
    % Manipulate Data
    directory = dir(data_dir);
    % sort by date
    dates = datetime({directory.date}, 'InputFormat', 'dd-MMM-yyyy HH:mm:ss');
    % Sort the dates and get the sorted indices
    [~, sortedIndices] = sort(dates);
    % Use the sorted indices to sort the structure array
    sortedDirectory = directory(sortedIndices);
    index_array = find(arrayfun(@(n) contains(sortedDirectory(n).name, 'CPD-R1-_BEH'),1:numel(sortedDirectory)));
    if length(index_array) > 1
        disp("WARNING, MULTIPLE BEHAVIORAL FILES FOUND FOR THIS ID. USING THE FIRST FULL ONE")
    end

    for k = 1:length(index_array)
        file_index = index_array(k);
        file = [data_dir sortedDirectory(file_index).name];

        subdat = readtable(file);
        % Practice is usually 60 trials but can be more/less. Games will always be 290 trials            
        % event code 15 signals early quit
        if any(subdat.event_code == 15)
            % if they made it passed trial 60, indicate that they have
            % practice effects and move on
            if max(subdat.trial_number) >= 60
                has_practice_effects = true;
            end
            continue;
        else
            % found a complete file!
            break;
        end
    end
    last_practice_trial = max(subdat.trial_number) - 290;
    first_game_trial = min(find(subdat.trial_number == last_practice_trial+1));
    clean_subdat = subdat(first_game_trial:end, :);
    
    
    clean_subdat_filtered = clean_subdat(clean_subdat.event_code==7 | clean_subdat.event_code==8 | clean_subdat.event_code==9,:);
    DCM.behavioral_file = clean_subdat_filtered;
    clean_subdat_filtered.accept_reject_rt = clean_subdat_filtered.response_time;
    % take the last 290 trials
    % event code 7 is game onset, event code 8 means they open a patch, event code 9 means they
    % accept dot motion.
    games = cell(1,290);
    for (trial_number=1:290)
        game = clean_subdat_filtered(clean_subdat_filtered.trial_number == trial_number+last_practice_trial,:);
        game.accept_reject_rt(1:end-1) = game.accept_reject_rt(2:end);  % Shift elements up
        game.accept_reject_rt{1} = 'NA';  % Set the first cell to 'NA'

        game = game(1:end-1,:);
        games(trial_number) = {game};
    end
    
    DCM.field  = fieldnames(DCM.MDP);
    DCM.U = games;
    DCM.Y = 0;
    
    CPD_fit_output= inversion_CPD(DCM);
    
    field = DCM.field;
    for i = 1:length(field)
        if any(strcmp(field{i},{'reward_lr','starting_bias', 'drift_mod'}))
            params.(field{i}) = 1/(1+exp(-CPD_fit_output.Ep.(field{i}))); 
        elseif any(strcmp(field{i},{'inverse_temp','decision_thresh'}))
            params.(field{i}) = exp( CPD_fit_output.Ep.(field{i}));           
        elseif any(strcmp(field{i},{'reward_prior', 'drift_baseline'}))
            params.(field{i}) =  CPD_fit_output.Ep.(field{i});
        else
            error("param not transformed");
        end
    end


    action_probabilities = CPD_RL_DDM_model(params, CPD_fit_output.U, 0);    
    patch_choice_action_prob = action_probabilities.patch_choice_action_prob;
    dot_motion_action_prob = action_probabilities.dot_motion_action_prob;
    rt_pdf = action_probabilities.dot_motion_rt_pdf;
    patch_choice_model_acc = action_probabilities.patch_choice_model_acc;
    dot_motion_model_acc = action_probabilities.dot_motion_model_acc;
    
    all_values = [patch_choice_action_prob(:); rt_pdf(:)];
    % Remove NaN values
    all_values = all_values(~isnan(all_values));
    % Take the log of the remaining values and sum them
    fit_results.id = subject_id;
    fit_results.has_practice_effects = has_practice_effects;
    fit_results.num_practice_trials = last_practice_trial + 1;
    fit_results.LL = sum(log(all_values));
    fit_results.patch_choice_avg_action_prob = mean(patch_choice_action_prob(~isnan(patch_choice_action_prob)));
    fit_results.patch_choice_avg_model_acc = mean(patch_choice_model_acc(~isnan(patch_choice_model_acc)));
    fit_results.dot_motion_avg_action_prob = mean(dot_motion_action_prob(~isnan(dot_motion_action_prob)));
    fit_results.dot_motion_avg_model_acc = mean(dot_motion_model_acc(~isnan(dot_motion_model_acc)));

    fit_results.F = CPD_fit_output.F;
    field = fieldnames(DCM.MDP);
    for i=1:length(field)
        fit_results.(['prior_' field{i}]) = DCM.MDP.(field{i});
    end
    for i=1:length(field)
        fit_results.(['fit_' field{i}]) = params.(field{i});
    end



end