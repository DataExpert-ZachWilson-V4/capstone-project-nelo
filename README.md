## STILL IN PROGRESS
## MORE UPDATES TO BE ADDED DAILY.

# MLB Game Stats Pipeline/Predictor/Chat-Bot

![MLB Diagram](/MLB_Diagram_Updated.png)

I used Ubuntu with Windows Subsystem for Linux (WSL 2), Docker Desktop and VS Code to complete this project.

### Download GitHub CLI: 
`sudo apt update`
`sudo apt install gh`
### Authenticate with your preferred method:
`gh auth login`
### In VS Code:
#### Clone & move into the repo directory:
`gh repo clone DataExpert-ZachWilson-V4/capstone-project-nelo-mlb-stats`

`cd capstone-project-nelo-mlb-stats`

### Azure VM Setup

Run `./trigger_workflow.sh`

This automates the setup of Azure VM using Terraform and GitHub Actions. Installs tools (Terraform, Azure CLI, sshpass), logs into Azure, verifies subscription access, generates SSH keys, initializes Terraform, applies Terraform changes to create or update resources, and retrieves the VM's public IP address. 

It waits for the VM to be in a running state, connects to it via SSH, installs Docker, Docker Compose, VS Code Server, and GitHub CLI, copies project files, and starts services with Docker Compose.

Run `ssh -i path/to/id_rsa azureuser@<PUBLIC_IP>` on your local machine to access VM 

**(Replace <PUBLIC_IP> with the public ip for the VM)**

#### Keep in mind to save these in .env file (instructions on where to find these are in .env file)

`RESOURCE_GROUP_NAME`
`STORAGE_ACCOUNT_NAME`
`ARM_CLIENT_ID`
`ARM_CLIENT_SECRET`
`ARM_TENANT_ID`
`ARM_SUBSCRIPTION_ID`

### When done:
#### Clean Up Docker Environment
Run `./clean_docker.sh`

## Overview
This project involves fetching historical & current MLB game stats from MLB.com API. Processing and storing the data in IceBerg tables. Training multiple ML models to predict future game stats of the current season, and storing these predictions back into Iceberg tables. As the days change, the future tables are overwritten daily to update predictions for upcoming games starting from the next day. The future date entries in these tables are shifted forward to the next future date, and the previous future day's data is replaced with the actual game data. All tables are converted to text embeddings using OpenAI's embeddings and stored in a Qdrant vector store. A RAG model is set up to retrieve the embeddings in Qdrant that match closest to the query embeddings generated by SentenceTransformers and combines into text prompts. These prompts are fed into OpenAI's GPT-3.5-turbo, which generates responses to user queries. The responses from OpenAI GPT are then displayed in the Streamlit app. The responses can also be converted to an audio file using gTTS (Google Text-to-Speech) and played back within the Streamlit app.

## Data Retrieval/Storage Process

#### Kafka

Kafka Producers are used to send MLB data (team/player info, stats/scores) in JSON format to Kafka topics. I used Pydantic models to validate and parse the data before sending it to Kafka. The producers determine the game range to be fetched using start_game and end_game arguments. This range is split among multiple threads to enable parallel data retrieval. Each script targets specific data types (like box scores or player info) and corresponds to a Kafka topic. For every game in the specified range, the producer constructs the API endpoint URL, sends an HTTP GET request, and, if necessary, retries up to five times using exponential backoff. To manage concurrency, I used ThreadPoolExecutor, which runs multiple scripts simultaneously. Semaphore limits the number of concurrent threads to avoid system overload. Tasks are batched and submitted in intervals to manage workload and reduce resource contention.

#### Spark Structured Streaming

Spark streams are used to process MLB game data from Kafka topics, dynamically process micro-batches to transform and perform aggregations, and store data in Iceberg tables using Azure Data Lake Storage. 

SCD Type 2 method is included to track changes in dimension data over time by maintaining multiple records for each. Each record represents a specific time period during which the data was valid. When new or updated records are detected, the current records in the dimension table are marked as inactive by setting an end date and updating the "is_current" flag to false. The new records, which represent the latest data, are inserted with a start date, a null end date, and the "is_current" flag set to true.

Cumulative and aggregate tables are created to track season totals and averages. `Cumulative Team & Player Season Totals` tables track the cumulative stats of teams & players for current season. `Aggregate Team & Player Season Totals` provide aggregated totals for each team & player per season. `Cumulative Team & Player Season Averages` provide running averages for team & player stats. `Aggregate Team & Players Season Averages` provide the average statistics for teams & players on a seasonal basis.

#### Data Quality with dbt

To ensure data quality, dbt (Data Build Tool) runs several tests on the tables stored in Iceberg. Including `Not Null` tests to ensure essential fields are not missing values, `No Duplicates` tests to verify the uniqueness of records, and checks to ensure numeric columns have `non-negative` values. `Data Type Consistency` tests confirm that fields conform to expected data types, `Accepted Values` tests ensure certain fields contain only valid values, and `date validity` checks confirm that date fields contain logical values.

#### Airflow

Apache Airflow will orchestrate the workflow on a daily schedule.

## ML Process

The tables stored in iceberg are read for future game info. Since future dates won't have actual stats, this focuses on extracting the scheduled matchups and their associated empty columns for predictions.

Feature selection using techniques like Lasso Regression  and Random Forest. 

Model training base regressors—AdaBoost, XGBoost, LightGBM, and Multivariate Linear Regression. These base models' predictions are stored and used in a stacking ensemble model.

Hyperparameter tuning is done using Bayesian Optimization. Used to identify the top 3 sets of hyperparameters for each base regressor, which are then evaluated using both Time Series Split and Monte Carlo cross-validation to determine the best performing parameters.

The final predictions are generated by a meta-regressor, CatBoost, which combines the base models' outputs, aiming to improve accuracy by learning the optimal integration of their predictions. 

Model metrics and predictions are logged in MLflow and stored in Azure PostgreSQL.

### Feature Selection
#### Lasso Regression

Also known as Least Absolute Shrinkage and Selection Operator, performs L1 regularization, which adds a penalty equal to the absolute value of the magnitude of the coefficients. This penalty forces some coefficients to become exactly zero, thus eliminating less important features from the model. By doing so, Lasso Regression helps in identifying the most significant features, such as runs, hits, and strikeouts, that are most relevant in predicting MLB game scores and outcomes over time.

$\hat{\beta} = \arg\min_{\beta} \left( \sum_{i=1}^{n} (y_i - X_i\beta)^2 + \lambda \sum_{j=1}^{p} |\beta_j| \right)$

where:
- $y_i$ is the response variable
- $X_i$ is the predictor variables
- $\beta$ are the coefficients
- $\lambda$ is the regularization parameter

#### Random Forest

Is an ensemble learning method that constructs multiple decision trees and outputs the mean prediction of the individual trees. It is known for handling a large number of features and reducing overfitting by averaging multiple decision trees. The prediction is calculated as the average of the predictions from all the decision trees.

$\hat{y} = \frac{1}{N} \sum_{i=1}^{N} T_i(x)$

where:
- $T_i(x)$ is the $i$-th decision tree
- $N$ is the number of trees

### Hyperparameter Tuning
#### Bayesian Optimization

Used to find the optimal parameters for the models by maximizing an objective function, which is typically the negative mean squared error in regression tasks. It starts by initializing with a few random hyperparameter sets to get an initial sense of the hyperparameter space. It then evaluates the objective function, typically the negative mean squared error, for these initial sets to understand their performance. In an iterative process, Bayesian Optimization updates a surrogate model based on the results of these evaluations, and uses an acquisition function to select new hyperparameters that balance exploration of the hyperparameter space with exploitation of known good areas. This process continues until it converges to the set of hyperparameters that yields the best model performance

For CatBoost, the parameter space includes `iterations`, `depth`, `learning_rate`, and `l2_leaf_reg`. Key hyperparameters for XGBoost include `n_estimators`, `max_depth`, `learning_rate`, `subsample`, and `colsample_bytree`. For LightGBM, hyperparameters like `num_leave`s, `max_depth`, `learning_rate`, `n_estimators`, and `min_child_samples` are tuned. And hyperparameters for AdaBoost such as `n_estimators` and `learning_rate` are optimized. Bayesian Optimization ensures that the weak learners combined in AdaBoost are tuned for the best performance.

$\text{Objective Function} = -\text{mean squared error}(y_{\text{train}}, \hat{y}_{\text{train}})$

### Models Training
#### AdaBoost

Or Adaptive Boosting, combines multiple weak learners to create a strong learner. It assigns higher weights to incorrectly predicted instances, focusing more on hard-to-predict cases in subsequent iterations. The final prediction is a weighted sum of the weak learners' predictions.

$f(x) = \sum_{t=1}^{T} \alpha_t h_t(x)$

where:
- $\alpha_t$ is the weight assigned to $t$-th weak learner
- $h_t(x)$ is the $t$-th weak learner
- $T$ is the total number of learners

#### XGBoost

An optimized distributed gradient boosting library designed to be highly efficient, flexible, and portable. It uses a regularization term in its objective function to prevent overfitting, which is the sum of the loss function and the regularization term over all trees. This optimization leads to better model performance and scalability.

![XGBOOST](/XGBOOST.png)

where:
- $\ell$ is the loss function
- $\Omega$ is the regularization term
- $f_k$ is the $k$-th tree
- $K$ is the number of trees

#### LightGBM
A gradient boosting framework that uses tree-based learning algorithms. It is designed to be distributed and efficient, capable of handling large datasets with high performance. LightGBM reduces memory usage and improves execution speed through techniques like histogram-based algorithms and leaf-wise tree growth.

$\hat{y} = \sum_{m=1}^{M} f_m(x)$

where:
- $f_m(x)$ is the $m$-th tree
- $M$ is the number of trees

#### Multivariate Linear Regression

Predicts a single target (e.g. game stat) variable using multiple predictor variables. 

$Y = \beta_0 + \beta_1 X_1 + \beta_2 X_2 + \cdots + \beta_p X_p + \epsilon$

where:
- $Y$ is the dependent variable (target variable).
- $X_1, X_2, \ldots, X_p$ are the independent variables (predictor variables).
- $\beta_0$ is the intercept term.
- $\beta_1, \beta_2, \ldots, \beta_p$ are the coefficients of the independent variables.
- $\epsilon$ is the error term (residuals).

#### CatBoost

A gradient boosting algorithm that handles categorical features effectively and reduces the need for extensive hyperparameter tuning. It constructs an ensemble of decision trees, where each tree is fit on the residuals of the previous trees. CatBoost is efficient in handling categorical variables without extensive preprocessing and speeds up training while reducing overfitting.

$F(x) = \sum_{t=1}^{T} \gamma_t G_t(x)$

where:
- $\gamma_t$ is the learning rate
- $G_t(x)$ is the $t$-th gradient boosted tree
- $T$ is the total number of trees

#### Stacking Regressor

Also known as a MetaRegressor, combines multiple base regressors—AdaBoost, XGBoost, Linear Regression, and LightGBM—by using CatBoost as the meta-regressor. Each base regressor is individually trained on the data, and their predictions are then used as input features for CatBoost. 
I want to see if Catboost will learn how to integrate the predictions from the base models to possibly provide a more accurate prediction compared to each individual model. Let's test this theory.

### Cross-Validations
#### Time Series Split

A cross-validation technique used when dealing with time series data. It ensures that the training set always precedes the test set in time. The data is split into $k$ consecutive folds, and each fold is used as a test set once while the preceding observations are used as the training set.

$\{(X_t, Y_t)\}_{t=1}^{T}$ is the time series data, where $X_t$ represents the features and $Y_t$ represents the target variable at time $t$. The splits are defined as follows:

![FOLDS](/FOLDS.png)

where $T_i$ are the split points. For each fold, the model is trained on the training set and evaluated on the test set. The performance metric, such as Mean Squared Error (MSE), is averaged across all folds to give the final evaluation metric.

#### Monte Carlo Cross-Validation

Also known as Shuffle-Split Cross-Validation, involves randomly splitting the dataset into training and test sets multiple times and evaluating the model on each split. This method helps to assess the stability and variability of the model’s performance.

Given a dataset $\{(X_i, Y_i)\}_{i=1}^{n}$, Monte Carlo Cross-Validation involves the following steps:

- Randomly split the dataset into a training set $\mathcal{T}_j$ and a test set $\mathcal{V}_j$ for $j = 1, 2, \ldots, m$.
- Train the model on the training set $\mathcal{T}_j$.
- Evaluate the model on the test set $\mathcal{V}_j$.
- Repeat steps 1-3 $m$ times.

The performance metric, Mean Squared Error (MSE), is computed for each split:

$\text{MSE} = \frac{1}{|\mathcal{V}|} \sum_{(X_i, Y_i) \in \mathcal{V}} (Y_i - \hat{Y}_i)^2$

where $\hat{Y}_i$ is the predicted value of $Y_i$.

The final performance metric is the average of the MSE values over all splits:

$\text{Average MSE} = \frac{1}{m} \sum_{j=1}^{m} \text{MSE}_j$

where:
- $m$ is the number of splits.
- $\mathcal{T}_j$ is the training set for the $j$-th split.
- $\mathcal{V}_j$ is the test set for the $j$-th split.
- $|\mathcal{V}_j|$ is the number of observations in the $j$-th test set.
- $(X_t, Y_t)$: Feature and target variable at time $t$.
- $t_j$: Split points for Time Series Split.
- $\mathcal{T}_j$: Training set for the $j$-th split in Monte Carlo Cross-Validation.
- $\mathcal{V}_j$: Test set for the $j$-th split in Monte Carlo Cross-Validation.
- $\text{MSE}_j$: Mean Squared Error for the $j$-th split.
- $\hat{Y}_i$: Predicted value of $Y_i$.
- $n$: Total number of observations.

#### Predictions & Model Metrics

Predictions are stored in Iceberg tables, with the data and metadata for these tables stored in Azure Data Lake Storage container. 

And the models, with their metrics, are logged using MLflow.

## RAG Model/Chat UI Process

Spark reads various tables containing past games and predicted game stats, including team and player statistics. These tables are transformed into a text format for natural language processing (NLP) tasks. The data is then fed into a pre-trained Sentence Transformers model to generate text embeddings. These embeddings capture the semantic meaning of the text data, making it easier to analyze and retrieve relevant information.

The generated text embeddings are sent to Qdrant, where it stores these embeddings in collections corresponding to different types of game data, such as team stats, player stats, and more.

And set up a question-and-answer pipeline using Haystack, Qdrant, and OpenAI GPT-3.5. with functions to fetch unique field values and team data based on user-selected criteria. The application allows users to ask questions, that are processed by splitting into sentences, cleaning input, and generating responses using OpenAI. Responses can be converted to audio using gTTS (Google Text-to-Speech). The sidebar provides options to select teams, players, seasons, and game types, and displays the corresponding team data and historical game results in an interactive UI.
