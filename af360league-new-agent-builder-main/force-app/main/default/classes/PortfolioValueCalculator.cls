public class PortfolioValueCalculator {
    
    // Get total portfolio value
    @InvocableMethod(label='Calculate Total Portfolio Value' 
                     description='Returns sum of financial account loan amounts. Optionally filter by status.')
    public static List<ValueResult> calculatePortfolioValue(List<InputRequest> requests) {
        // Get input parameters (default to 'Active' status if not provided)
        String status = 'Active';
        
        if (requests != null && requests.size() > 0 && requests[0] != null) {
            InputRequest input = requests[0];
            if (input.status != null && input.status != '') {
                status = input.status;
            }
        }
        
        // Query financial accounts with optional filters
        String query = 'SELECT Id, Original_Loan_Amount__c FROM FinancialAccount WHERE Status = :status';
        
        List<FinancialAccount> accounts = Database.query(query);
        
        Decimal totalValue = 0;
        for (FinancialAccount account : accounts) {
            if (account.Original_Loan_Amount__c != null) {
                totalValue += account.Original_Loan_Amount__c;
            }
        }
        
        ValueResult result = new ValueResult();
        result.totalValue = totalValue;
        
        return new List<ValueResult>{ result };
    }
    
    // Input wrapper class for agent parameters
    public class InputRequest {
        @InvocableVariable(label='Status' 
                          description='Optional: Filter by status (e.g., Active, Closed). Defaults to Active if not provided.')
        public String status;
    }
    
    // Output wrapper class for invocable method results
    public class ValueResult {
        @InvocableVariable(label='Total Portfolio Value' 
                           description='The sum of all financial account loan amounts matching the specified filters')
        public Decimal totalValue;
    }
}

