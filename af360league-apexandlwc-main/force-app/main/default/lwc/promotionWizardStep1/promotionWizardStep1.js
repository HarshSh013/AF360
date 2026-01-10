import { LightningElement, api } from 'lwc';

/** TODO FOR THE CHALLENGE: import the state manager, and the context modules */
import promotionStateService from 'c/promotionStateService';

export default class PromotionWizardStep1 extends LightningElement {
    
    /** TODO FOR THE CHALLENGE: initialize/inherit the state from the parent */
    stateService = promotionStateService;
    promotionName = '';

    connectedCallback(){
        this.promotionName = this.promotionState?.value?.promotionName;
    }

    handleChange(event) {
        this.promotionName = event.detail.value;
    }

    @api
    allValid(){
        if(this.promotionName === undefined || this.promotionName === ''){
            return false;
        }
        
        // TODO FOR THE CHALLENGE: Update the promotion name in the state
        console.log('Validation passed. Updating state...');
        this.stateService.updatePromotionName(this.promotionName);
        
        // Verify the state was updated
        const updatedState = this.stateService.getState();
        console.log('State after update:', updatedState);
        
        return true;
    }
}