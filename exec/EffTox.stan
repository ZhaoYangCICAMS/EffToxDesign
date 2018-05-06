// Dose-Finding Based on Efficacy-Toxicity Trade-Offs, by Thall, Cook
// Effective sample size for computing prior hyperparameters in Bayesian phase I-II dose-finding,
//  by Thall, Herrick, Nguyen, Venier, Norris

functions {
  real log_joint_pdf(real[] coded_doses, real[] coded_doses_squ,
                     int num_patients, int[] eff, int[] tox, int[] doses,
                     real muT, real betaT1, real muE, real betaE1, real betaE2, real psi) {
    real p;
    p = 0;
    for(j in 1:num_patients) {
      real prob_eff;
      real prob_tox;
      real p_j;
      prob_eff = inv_logit(muE + betaE1 * coded_doses[doses[j]] + betaE2 * coded_doses_squ[doses[j]]);
      prob_tox = inv_logit(muT + betaT1 * coded_doses[doses[j]]);
      p_j = prob_eff^eff[j] * (1 - prob_eff)^(1 - eff[j]) * prob_tox^tox[j] *
              (1 - prob_tox)^(1 - tox[j]) + (-1)^(eff[j] + tox[j]) * prob_eff *
              prob_tox * (1 - prob_eff) * (1 - prob_tox) * (exp(psi) - 1) / (exp(psi) + 1);
      p = p + log(p_j);
    }
    return p;
  }
}

data {
  // Hyperparameters
  real muT_mean;
  real<lower=0> muT_sd;
  real betaT1_mean;
  real<lower=0> betaT1_sd;
  real muE_mean;
  real<lower=0> muE_sd;
  real betaE1_mean;
  real<lower=0> betaE1_sd;
  real betaE2_mean;
  real<lower=0> betaE2_sd;
  real psi_mean;
  real<lower=0> psi_sd;
  // Fixed trial parameters
  int<lower=1> num_doses;
  real<lower=0> real_doses[num_doses]; // Doses under investigation, e.g. 10, 20, 30 for 10mg, 20mg, 30mg
  real p;  // The p of the L^p norm used to model the efficacy-toxicity indifference contours.
           // See Efficacy-Toxicity trade-offs based on L-p norms: Technical Report UTMDABTR-003-06
  real eff0; // Minimum required Pr(Efficacy) when Pr(Toxicity) = 0
  real tox1; // Maximum permissable Pr(Toxicity) when Pr(Efficacy) = 1
  real efficacy_hurdle; // A dose is acceptable if prob(eff) exceeds this hurdle...
  real toxicity_hurdle; //  ... and prob(tox) is less than this hurdle
  // Observed trial outcomes
  int<lower=0> num_patients;
  int<lower=0, upper=1> eff[num_patients]; // Binary efficacy event for patients j=1,..,num_patients
  int<lower=0, upper=1> tox[num_patients]; // Binary toxicity event for patients j=1,..,num_patients
  int<lower=1, upper=num_doses> doses[num_patients];  // Dose-levels given for patients j=1,..,num_patients.
                                   // Dose-levels are 1-based indices of real_doses
                                   // E.g. 1 means 1st dose in real_doses was given
}

transformed data {
  // Thall & Cook transform the actual doses by logging and centralising:
  real coded_doses[num_doses];
  real coded_doses_squ[num_doses]; // The square of coded_doses
  real mean_log_dose; // Variable created for convenience
  mean_log_dose = 0.0;
  for(i in 1:num_doses)
    mean_log_dose = mean_log_dose + log(real_doses[i]);
  mean_log_dose = mean_log_dose / num_doses;
  for(i in 1:num_doses)
  {
    coded_doses[i] = log(real_doses[i]) - mean_log_dose;
    coded_doses_squ[i] = coded_doses[i]^2;
  }
}

parameters {
  // Coefficients in toxicity logit model:
  real muT;
  real betaT1;
  // Coefficients in efficacy logit model:
  real muE;
  real betaE1;
  real betaE2;
  // Association:
  real psi;
}

transformed parameters {
  real<lower=0, upper=1> prob_eff[num_doses]; // Posterior probability of efficacy at doses i=1,...,num_doses
  real<lower=0, upper=1> prob_tox[num_doses]; // Posterior probability of toxicity at doses i=1,...,num_doses
  real<lower=0, upper=1> prob_acc_eff[num_doses]; // Probability efficacy is acceptable at doses i=1,...,num_doses
  real<lower=0, upper=1> prob_acc_tox[num_doses]; // Probability toxicity is acceptable at doses i=1,...,num_doses
  real utility[num_doses]; // Posterior utility of doses i=1,...,num_doses
  // Calculate the utility of each dose using the method described in
  // "Efficacy-Toxicity trade-offs based on L-p norms: Technical Report UTMDABTR-003-06", John Cook
  for(i in 1:num_doses)
  {
    real r_to_the_p; // Convenience variable, as in (2) of Cook.
    prob_tox[i] = inv_logit(muT + betaT1 * coded_doses[i]);
    prob_eff[i] = inv_logit(muE + betaE1 * coded_doses[i] + betaE2 * coded_doses_squ[i]);
    prob_acc_eff[i] = int_step(prob_eff[i] - efficacy_hurdle);
    prob_acc_tox[i] = int_step(toxicity_hurdle - prob_tox[i]);
    r_to_the_p = ((1 - prob_eff[i]) / (1 - eff0))^p + (prob_tox[i] / tox1)^p;
    utility[i] = 1 - r_to_the_p ^ (1.0/p);
  }
}

model {
  target += normal_lpdf(muT | muT_mean, muT_sd);
  target += normal_lpdf(betaT1 | betaT1_mean, betaT1_sd);
  target += normal_lpdf(muE | muE_mean, muE_sd);
  target += normal_lpdf(betaE1 | betaE1_mean, betaE1_sd);
  target += normal_lpdf(betaE2 | betaE2_mean, betaE2_sd);
  target += normal_lpdf(psi | psi_mean, psi_sd);
  target += log_joint_pdf(coded_doses, coded_doses_squ, num_patients, eff, tox, doses,
                          muT, betaT1, muE, betaE1, betaE2, psi);
}
