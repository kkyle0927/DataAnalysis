function importCSVData
    % Function to import a CSV file and categorize data intelligently
    % Optimized to handle large CSV files efficiently

    % Use uigetfile to prompt the user to select a CSV file
    [file, path] = uigetfile('*.csv', 'Select CSV file to import');
    if isequal(file, 0)
        disp('User selected Cancel');
        return;
    else
        filename = fullfile(path, file);
        disp(['User selected ', filename]);
    end

    % Initialize waitbar
    hWaitbar = waitbar(0, 'Loading data...', 'Name', 'Importing CSV Data', ...
                       'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
    setappdata(hWaitbar, 'canceling', 0);

    % Read the file into cell array line by line with progress update
    fid = fopen(filename, 'r');

    % Count total number of lines for progress estimation
    totalFileLines = 0;
    while ~feof(fid)
        fgets(fid);
        totalFileLines = totalFileLines + 1;
    end
    frewind(fid);  % Reset file pointer to the beginning

    fileLines = {};
    tline = fgetl(fid);
    lineCounter = 0;
    updateInterval = 1000;  % Adjust as needed for performance

    while ischar(tline)
        fileLines{end + 1} = tline;
        lineCounter = lineCounter + 1;

        % Update waitbar periodically
        if mod(lineCounter, updateInterval) == 0 || feof(fid)
            waitbar(lineCounter / totalFileLines, hWaitbar, ...
                sprintf('Loading data... (%d%%)', floor((lineCounter / totalFileLines) * 100)));
            % Check for Cancel button press
            if getappdata(hWaitbar, 'canceling')
                fclose(fid);
                delete(hWaitbar);
                disp('Loading canceled by user.');
                return;
            end
        end

        tline = fgetl(fid);
    end
    fclose(fid);

    % Close the waitbar after loading
    delete(hWaitbar);

    % Process the file
    lineNum = 1;
    totalLines = length(fileLines);
    mainCategories = [];
    mainCategoryIndex = 0;
    while lineNum <= totalLines
        % Skip empty lines
        while lineNum <= totalLines && isempty(strtrim(fileLines{lineNum}))
            lineNum = lineNum + 1;
        end
        if lineNum > totalLines
            break;
        end
        % Main Category name
        mainCategoryName = strtrim(fileLines{lineNum});
        mainCategoryIndex = mainCategoryIndex + 1;
        lineNum = lineNum + 1;
        if lineNum > totalLines
            break;
        end
        % Sampling Frequency
        samplingFreqLine = fileLines{lineNum};
        samplingFreq = strtrim(samplingFreqLine);
        lineNum = lineNum + 1;
        if lineNum > totalLines
            break;
        end
        % Subcategory line
        subCategoryLine = fileLines{lineNum};
        % Add "Time," at the beginning
        subCategoryLine = [mainCategoryName '_Time' subCategoryLine];
        lineNum = lineNum + 1;
        if lineNum > totalLines
            break;
        end
        % Data Categories line
        dataCategoryLine = fileLines{lineNum};
        lineNum = lineNum + 1;
        if lineNum > totalLines
            break;
        end
        % Units line
        unitsLine = fileLines{lineNum};
        lineNum = lineNum + 1;
        % Data lines
        dataLines = {};
        while lineNum <= totalLines && ~isempty(strtrim(fileLines{lineNum}))
            dataLines{end + 1} = fileLines{lineNum};
            lineNum = lineNum + 1;
        end
        % Process this block
        % Parse subcategories, data categories, and units, preserving empty strings
        subCategories = strsplit(subCategoryLine, ',', 'CollapseDelimiters', false);
        subCategories = subCategories(1:end-1);
        dataCategories = strsplit(dataCategoryLine, ',', 'CollapseDelimiters', false);
        units = strsplit(unitsLine, ',', 'CollapseDelimiters', false);

        % Determine the number of data categories for each subcategory
        subcategoryList = [];
        subCatIndex = 1;
        i = 1;
        while i <= length(subCategories)
            if ~isempty(subCategories{i})
                subcategoryName = strtrim(subCategories{i});
                numBlanks = 0;
                j = i + 1;
                while j <= length(subCategories) && isempty(subCategories{j})
                    numBlanks = numBlanks + 1;
                    j = j + 1;
                end
                % The number of data categories is the number of blanks + 1
                numDataCategories = numBlanks + 1;
                subcategoryList(subCatIndex).name = subcategoryName;
                subcategoryList(subCatIndex).numDataCategories = numDataCategories;
                subCatIndex = subCatIndex + 1;
                i = j;
            else
                i = i + 1;
            end
        end

        % Assign dataCategories and units to subcategories
        dataCatIndex = 1;
        for k = 1:length(subcategoryList)
            numDataCategories = subcategoryList(k).numDataCategories;
            if dataCatIndex + numDataCategories - 1 <= length(dataCategories)
                subcategoryList(k).dataCategories = dataCategories(dataCatIndex:dataCatIndex + numDataCategories - 1);
                subcategoryList(k).units = units(dataCatIndex:dataCatIndex + numDataCategories - 1);
            else
                error('Mismatch in data categories and subcategories.');
            end
            dataCatIndex = dataCatIndex + numDataCategories;
        end

        % Read dataLines into dataMatrix
        dataText = strjoin(dataLines, '\n');
        formatSpec = repmat('%f', 1, length(dataCategories));
        dataArray = textscan(dataText, formatSpec, 'Delimiter', ',', 'CollectOutput', true);
        dataMatrix = dataArray{1};

        % Assign data to subcategories
        dataCatIndex = 1;
        for k = 1:length(subcategoryList)
            numDataCategories = subcategoryList(k).numDataCategories;
            indices = dataCatIndex:dataCatIndex + numDataCategories - 1;
            subData = dataMatrix(:, indices);
            subcategoryList(k).data = subData;
            dataCatIndex = dataCatIndex + numDataCategories;
        end

        % Store in mainCategories
        mainCategories(mainCategoryIndex).name = mainCategoryName;
        mainCategories(mainCategoryIndex).samplingFreq = samplingFreq;
        mainCategories(mainCategoryIndex).subcategories = subcategoryList;

        % Move past any empty lines indicating end of main category
        while lineNum <= totalLines && isempty(strtrim(fileLines{lineNum}))
            lineNum = lineNum + 1;
        end
    end

    % Now, display GUI with tabs
    f = figure('Name', 'Select Data', 'Position', [700, 100, 600, 700]);
    
    % Create a tab group that fills most of the figure window
    tabGroup = uitabgroup('Parent', f, 'Position', [0, 0.1, 1, 0.9]);
    subCatListboxes = cell(1, length(mainCategories));
    
    for idx = 1:length(mainCategories)
        mainCat = mainCategories(idx);
        tab = uitab('Parent', tabGroup, 'Title', mainCat.name);
        % Get subcategory names
        subCats = mainCat.subcategories;
        subCatNames = {subCats.name};
        % Create listbox in tab
        subCatListboxes{idx} = uicontrol('Parent', tab, 'Style', 'listbox', ...
            'Units', 'normalized', 'Position', [0.05, 0.05, 0.9, 0.85], ...
            'String', subCatNames, 'Max', 2, 'Min', 0);
        uicontrol('Parent', tab, 'Style', 'text', ...
            'Units', 'normalized', 'Position', [0.05, 0.92, 0.9, 0.05], ...
            'String', 'Subcategories', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    end
    
    % Add "OK" and "Save all" buttons at the bottom of the figure
    saveAllButton = uicontrol('Style', 'pushbutton', 'String', 'Save all', ...
        'Units', 'normalized', 'Position', [0.6, 0.02, 0.15, 0.06], ...
        'Callback', @saveAllButtonCallback);
    okButton = uicontrol('Style', 'pushbutton', 'String', 'OK', ...
        'Units', 'normalized', 'Position', [0.8, 0.02, 0.15, 0.06], ...
        'Callback', @okButtonCallback);

    % Callback functions
    function okButtonCallback(~, ~)
        for idx = 1:length(mainCategories)
            mainCat = mainCategories(idx);
            subCatListbox = subCatListboxes{idx};
            subCatIndices = get(subCatListbox, 'Value');
            if isempty(subCatIndices)
                continue;
            end
            selectedSubCats = mainCat.subcategories(subCatIndices);
            for s = 1:length(selectedSubCats)
                subCat = selectedSubCats(s);
                % Create variable name
                varName = [subCat.name];
                % varName = [mainCat.name '_' subCat.name];
                % Replace invalid characters
                varName = regexprep(varName, '[^a-zA-Z0-9_]', '_');
                % Remove multiple underscores
                varName = regexprep(varName, '_+', '_');
                % If starts with number, add 'x'
                if ~isempty(varName) && ~isletter(varName(1))
                    varName = ['x' varName];
                end
                % Now, create struct variable
                dataStruct = struct();
                dataCategories = subCat.dataCategories;
                units = subCat.units;
                data = subCat.data;
                % For each data category, create field
                for d = 1:length(dataCategories)
                    fieldName = dataCategories{d};
                    % Process field name
                    fieldName = regexprep(fieldName, '[^a-zA-Z0-9_]', '_');
                    fieldName = regexprep(fieldName, '_+', '_');
                    fieldName = strtrim(fieldName); % Trim whitespace
                    if isempty(fieldName)
                        % Skip this iteration if fieldName is empty
                        continue;
                    end
                    if ~isletter(fieldName(1))
                        fieldName = ['x' fieldName];
                    end
                    % Handle empty units
                    unitStr = '';
                    if d <= length(units)
                        unitStr = units{d};
                    end
                    dataStruct.(fieldName).data = data(:, d);
                    dataStruct.(fieldName).units = unitStr;
                end
                % Save dataStruct to workspace
                assignin('base', varName, dataStruct);
            end
        end
        disp('Selected data has been imported into the workspace.');
    end

    function saveAllButtonCallback(~, ~)
        % Build a struct to save all variables
        variablesToSave = struct();
        for idx = 1:length(mainCategories)
            mainCat = mainCategories(idx);
            subCats = mainCat.subcategories;
            for s = 1:length(subCats)
                subCat = subCats(s);
                % Create variable name
                varName = subCat.name;
                % Replace invalid characters
                varName = regexprep(varName, '[^a-zA-Z0-9_]', '_');
                varName = regexprep(varName, '_+', '_');
                % If starts with number, add 'x'
                if ~isempty(varName) && ~isletter(varName(1))
                    varName = ['x' varName];
                end
                % Now, create struct variable
                dataStruct = struct();
                dataCategories = subCat.dataCategories;
                units = subCat.units;
                data = subCat.data;
                % For each data category, create field
                for d = 1:length(dataCategories)
                    fieldName = dataCategories{d};
                    % Process field name
                    fieldName = regexprep(fieldName, '[^a-zA-Z0-9_]', '_');
                    fieldName = regexprep(fieldName, '_+', '_');
                    fieldName = strtrim(fieldName); % Trim whitespace
                    if isempty(fieldName)
                        % Skip this iteration if fieldName is empty
                        continue;
                    end
                    if ~isletter(fieldName(1))
                        fieldName = ['x' fieldName];
                    end
                    % Handle empty units
                    unitStr = '';
                    if d <= length(units)
                        unitStr = units{d};
                    end
                    dataStruct.(fieldName).data = data(:, d);
                    dataStruct.(fieldName).units = unitStr;
                end
                % Add dataStruct to variablesToSave
                variablesToSave.(varName) = dataStruct;
            end
        end
        % Save variablesToSave struct to .mat file, unpacking variables
        [~, baseFileName, ~] = fileparts(filename);
        matFileName = [baseFileName '.mat'];
        save(matFileName, '-struct', 'variablesToSave');
        disp(['All data has been saved to ' matFileName]);
    end

end
