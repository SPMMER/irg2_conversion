clear

mainfolder = 'D:\conversion\mouse_reference_data\'; %fullfile(cd, '\test_cell\');
outputfolder = 'D:\output_NeuroNex_reference\'; %[cd, '\'];
cellList = getCellNames(mainfolder);
T = readtable([mainfolder, 'manual_entry_data.csv']);
sessionTag = 'M00';  
filetag = 0;

for n = 1:length(cellList)
    
    cellID = cellList(n).name;
    disp(cellID)  
    fileList = dir([mainfolder,cellList(n,1).name,'/*.abf']);
    %% Initializing variables for Sweep table construction
    
    noManuTag = 0;
    sweepCount = 1;
    sweep_series_objects_ch1 = []; sweep_series_objects_ch2 = [];
    SweepAmp = [];stimOff = []; stimOnset = []; 
    %% Initializing nwb file and adding first global descriptors
    nwb = NwbFile();
    nwb.identifier = cellList(n,1).name;
    nwb.session_description = ...
      'Characterizing intrinsic biophysical properties of cortical NHP neurons';
    idx = find(strcmp(T.IDS, cellID));
    if isempty(idx)
        disp('Manual entry data not found')
        noManuTag = 1;
         nwb.general_subject = types.core.Subject( ...
      'description', 'NA', 'age', 'NA', ...
      'sex', 'NA', 'species', 'NA');
       corticalArea = 'NA'; 
       initAccessResistance = 'NA';
    else    
      nwb.general_subject = types.core.Subject( ...
        'subject_id', T.SubjectID(idx), 'age', num2str(T.SubjectAge_years(idx)), ...
        'sex', T.SubjectSex(idx), 'species', T.SubjectBreed(idx), ...
        'weight', num2str(T.SubjectWeight_Kg(idx))     ... 
         );      
       corticalArea = T.TissueOrigin(idx);
       initAccessResistance = num2str(T.InitialAccessResistance(idx));
    end
     nwb.general_institution = 'University of Western Ontario';
     device_name = 'Amplifier';
     nwb.general_devices.set(device_name, ...
         types.core.Device('description', 'Axon MultiClamp 700B', ...
                                 'manufacturer', 'Molecular Devices'));
                             
     nwb.general_devices.set('Digitizer', ...
         types.core.Device('description', 'Axon Digidata 1440 or 1550', ...
                                 'manufacturer', 'Molecular Devices'));     

     if noManuTag==0 && cell2mat(T.SlicingSolution(idx))=="Choline"
       nwb.general_surgery = 'Bioopsies; Anaesthesia; choline-based slicing solution';     
     end
     
     nwb.general_slices = 'ACSF slightly different to NeuroNex better description follows';
     nwb.general_source_script = 'custom matlab script using MATNWB';
     nwb.general_source_script_file_name = mfilename;
     
     %% Add anatomical data from histological processing
     
     anatomy = types.core.ProcessingModule(...
                         'description', 'Histological processing',...
                         'dynamictable', []  ...
                               );     
                           
     table = table2nwb(T(idx,11:12));  
     anatomy.dynamictable.set('Anatomical data', table);
     nwb.processing.set('Anatomical data', anatomy);
                           
    %% loading the abf files
    paths = fullfile({fileList.folder}, {fileList.name});
    for f = 1:length(fileList)
        
        settingsMCC = [];
        [data,sample_int,aquiPara] = abfload(paths{1,f}, ...
            'sweeps','a','channels','a');
    %% Getting start date from 1st recording of cell and checking for new session start 
        if f==1 
           cellStart = datetime(aquiPara.uFileStartDate, 'ConvertFrom', 'yyyymmdd' ...
            ,'TimeZone', 'local')+ seconds(aquiPara.uFileStartTimeMS/1000);
           if strcmp(sessionTag, cell2mat(T.SubjectID(idx)))
               nwb.session_start_time = sessionStart;
           else
            sessionStart = cellStart;
            nwb.session_start_time = sessionStart;
            sessionTag = cell2mat(T.SubjectID(idx));
           end 
        end
    %% load JSON files if present    
        if isfile([mainfolder,cellID,'\', fileList(f).name(1:end-3), 'json'])
          raw = fileread([mainfolder,cellID,'\', fileList(f).name(1:end-3), 'json']); 
          settingsMCC = jsondecode(raw);
          cellsFieldnames = fieldnames(settingsMCC);               
          ic_elec_name = cellsFieldnames{1, 1}(2:end);
          electOffset = settingsMCC.(cellsFieldnames{1,1}).GetPipetteOffset; 
         else
          ic_elec_name = 'unknown'; 
          electOffset = NaN;
        end 
         
   %% Assign parameters from settingsMCC
   if isempty(settingsMCC)
      filterFreq = 'NA';
      brigBal = [];
      holdI = [];
      capComp = [];
      PipOffset= [];
   else
       filterFreq = num2str(settingsMCC.(['x', ic_elec_name]).GetPrimarySignalLPF);
       PipOffset = settingsMCC.(['x', ic_elec_name]).GetPipetteOffset;  
       if settingsMCC.(['x', ic_elec_name]).GetBridgeBalEnable
          brigBal = settingsMCC.(['x', ic_elec_name]).GetBridgeBalResist;  
       else
          brigBal = 0;
       end
       if settingsMCC.(['x', ic_elec_name]).GetHoldingEnable
         holdI = settingsMCC.(['x', ic_elec_name]).GetHolding;
       else
         holdI = 0;
       end
       if settingsMCC.(['x', ic_elec_name]).GetNeutralizationEnable  
          capComp = settingsMCC.(['x', ic_elec_name]).GetNeutralizationCap;  
       else
          capComp = 0; 
       end
       
   end
   
   %% Getting run and electrode associated properties  
        device_link = types.untyped.SoftLink(['/general/devices/', device_name]); % lets see if that works
        ic_elec = types.core.IntracellularElectrode( ...
            'device', device_link, ...
            'description', 'Properties of electrode and run associated to it',...
            'filtering', filterFreq ,...
            'initial_access_resistance',initAccessResistance,...
            'location', corticalArea,...
            'slice', ['Temperature ', num2str(T.Temperature(idx))]...
        );
        nwb.general_intracellular_ephys.set(ic_elec_name, ic_elec);
        ic_elec_link = types.untyped.SoftLink(['/general/intracellular_ephys/' ic_elec_name]);       
    %% Data: recreating the stimulus waveform
        stimulus_name = aquiPara.protocolName(...
            find(aquiPara.protocolName=='\',1, 'last')+1:end);
        
        if isempty(aquiPara.DACEpoch) && ~contains(aquiPara.protocolName, 'noise')           
           
            nwb.acquisition.set(['Sweep_', num2str(sweepCount-1)], ...
            types.core.IZeroClampSeries( ...
                'bridge_balance', brigBal, ... % Unit: Ohm
                'capacitance_compensation', capComp, ... % Unit: Farad
                'data', data, ...
                'data_unit', 'mV', ...
                'electrode', ic_elec_link, ...
                'stimulus_description', stimulus_name,...
                'starting_time',aquiPara.uFileStartTimeMS\1000,...
                'starting_time_rate', 1000000/sample_int,...
                'sweep_number', sweepCount ...
            ));                           
              
              sweep_ch2 = types.untyped.ObjectView(['/acquisition/', 'Sweep_', num2str(sweepCount-1)]);
              sweep_series_objects_ch2 = [sweep_series_objects_ch2, sweep_ch2];
              SweepAmp(sweepCount,1) = NaN;
              stimOff(sweepCount,1) = NaN;
              stimOnset(sweepCount,1) = NaN;
              sweepCount =  sweepCount + 1;   
              
        elseif ~contains(aquiPara.protocolName, 'noise')  
            
            if sample_int == 100
                 constantShift = 3126; 
            elseif sample_int == 200                % shift for input versus response
               constantShift = 3124*0.5;
            elseif  sample_int == 50            
                constantShift = 6268;
                if sum(fileList(f).name(1:4)=='2018')==4 ...
                        || sum(fileList(f).name(1:2)=='18')==2 ...
                        || sum(fileList(f).name(1:4)=='2019')==4 ...
                        || sum(fileList(f).name(1:2)=='19')==2     ...
                        || sum(fileList(f).name(1:2)=='21')==2 ...
                        || sum(fileList(f).name(1:4)=='2021')==4
                    constantShift = 3126;        
                end      
                
            elseif  sample_int == 20
                %constantShift = 6268;        %Macaque
                constantShift = 3126;         %Marm
            end
            
            stimInd = find(aquiPara.DACEpoch.fEpochLevelInc~=0);                
            stimOnset(sweepCount:size(data,3)+sweepCount-1,1) = sum(aquiPara.DACEpoch.lEpochInitDuration(...
                1:stimInd-1))+constantShift;
            stimDuration = aquiPara.DACEpoch.lEpochInitDuration(stimInd);
            stimOff(sweepCount:size(data,3)+sweepCount-1,1)  = ...
                   stimOnset(sweepCount:size(data,3)+sweepCount-1,1) + stimDuration; 
            
             if  stimDuration*(sample_int/1000) == 1000 
                 stimDescrp = 'Long Pulse';             
             elseif stimDuration*(sample_int/1000) == 3
                 stimDescrp = 'Short Pulse';
             else
                 disp('hi')
             end
             
%             if filetag == 0
%                LPname = aquiPara.protocolName;
%                SPname = [];
%             elseif string(aquiPara.protocolName) ~= string(LPname)  && isempty(SPname)
%                SPname = aquiPara.protocolName;
%             end
            
            for s = 1:size(data,3)
                
%                 if string(aquiPara.protocolName) == string(LPname) || ...
%                    string(aquiPara.protocolName) == string(SPname)
%                
%                     AllenTag(sweepCount,1) = 1;
%                 else
%                     AllenTag(sweepCount,1) = 0;
%                 end
                SweepAmp(sweepCount,1)  =  aquiPara.DACEpoch.fEpochInitLevel(stimInd)+ ...
                          aquiPara.DACEpoch.fEpochLevelInc(stimInd)*s;
                      
                stimData = [zeros(1,stimOnset(sweepCount,1)), ...
                             ones(1,stimDuration).*SweepAmp(sweepCount,1),...
                               zeros(1,length(data)- ...
                                stimOnset(sweepCount,1)-stimDuration)]';

                         
                ccs = types.core.CurrentClampStimulusSeries( ...
                        'electrode', ic_elec_link, ...
                        'gain', NaN, ...
                        'stimulus_description', stimDescrp, ...
                        'data_unit', 'pA', ...
                        'data', stimData, ...
                        'sweep_number', sweepCount,...
                        'starting_time', aquiPara.uFileStartTimeMS/1000,...
                        'starting_time_rate', 1000000/sample_int...
                        );
                    
                nwb.stimulus_presentation.set(['Sweep_', num2str(sweepCount-1)], ccs);    

                nwb.acquisition.set(['Sweep_', num2str(sweepCount-1)], ...
                    types.core.CurrentClampSeries( ...
                        'bias_current', holdI, ... % Unit: Amp
                        'bridge_balance', brigBal, ... % Unit: Ohm
                        'capacitance_compensation', capComp, ... % Unit: Farad
                        'data', data(:,1,s), ...
                        'data_unit', aquiPara.recChUnits{:}, ...
                        'electrode', ic_elec_link, ...
                        'stimulus_description', stimDescrp, ...   
                        'sweep_number', sweepCount,...
                        'starting_time', aquiPara.uFileStartTimeMS/1000,...
                        'starting_time_rate', 1000000/sample_int...
                          ));
                    
                sweep_ch2 = types.untyped.ObjectView(['/acquisition/', 'Sweep_', num2str(sweepCount-1)]);
                sweep_ch1 = types.untyped.ObjectView(['/stimulus/presentation/', 'Sweep_', num2str(sweepCount-1)]);
                sweep_series_objects_ch1 = [sweep_series_objects_ch1, sweep_ch1]; 
                sweep_series_objects_ch2 = [sweep_series_objects_ch2, sweep_ch2];
                sweepCount =  sweepCount + 1;   
            end
            filetag = filetag + 1;        
        end
    end
    
%% Sweep table
     sweeppaths = [sweep_series_objects_ch1, sweep_series_objects_ch2]; 
        
     sweep_inds_ch2 = [0:length(sweep_series_objects_ch2)-1];
     sweep_inds_vec = [[sweep_inds_ch2(~isnan(stimOnset))],[sweep_inds_ch2]];
     
     sweep_nums_vec = sweep_inds_vec + 1;
     
%    AllenTag_vec = [AllenTag; AllenTag]';
    
     sweep_nums = types.hdmf_common.VectorData('data', sweep_nums_vec, ...
                                  'description','sweep numbers');                                     
    series_ind = types.hdmf_common.VectorIndex(...
          'data', sweep_inds_vec,...                                      % 0-based indices to sweep_series_objects
           'target', types.untyped.ObjectView('/general/intracellular_ephys/sweep_table/series'));
    series_data = types.hdmf_common.VectorData(...
                      'data', sweeppaths,...
                      'description', 'Jagged Array of Patch Clamp Series Objects');

    sweepTable = types.core.SweepTable(...
        'colnames', {'series', 'sweep_number', 'Allen_tag'},...
        'description', 'Sweep table for single electrode aquisitions; traces from current injection are reconstructed',...
        'id', types.hdmf_common.ElementIdentifiers('data',  [0:length(sweep_nums_vec)-1]),...
        'series_index', series_ind,...
        'series', series_data,...
        'sweep_number', sweep_nums...
        );

    nwb.general_intracellular_ephys_sweep_table = sweepTable;
    
        nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'SweepAmp') = ...
          types.hdmf_common.VectorData(...
           'description', 'amplitdue of the current step injected (if square pulse)',...
           'data',[[SweepAmp(~isnan(SweepAmp))]', [SweepAmp]']...
              ); 
          
    nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'StimOn') = ...
          types.hdmf_common.VectorData(...
           'description', 'Index of stimulus onset',...
           'data', [[stimOnset(~isnan(stimOnset))]', [stimOnset]']...
              );   
              
    nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'StimOff') = ...
          types.hdmf_common.VectorData(...
           'description', 'Index of end of stimulus',...
           'data', [[stimOff(~isnan(stimOff))]', [stimOff]']...
              ); 
          
    StimDuration = [];
    StimDuration = stimOff - stimOnset;   
    nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'StimLength') = ...
          types.hdmf_common.VectorData(...
           'description', 'Stimulus Length',...
           'data', [[StimDuration(~isnan(StimDuration))]', [StimDuration]']...
              );   
          
%%    
    sessionTag = cell2mat(T.SubjectID(idx));
    filename = fullfile([outputfolder ,nwb.identifier '.nwb']);
    nwbExport(nwb, filename);
end    