#linking if mismatches

unlinked_allo_clinical <- linking_allo %>% 
  filter(!is.na(allozithro_id) & !(allozithro_id %in% linked$allozithro_id))

length(unique(unlinked_allo_clinical$allozithro_id))
#11

unlinked_allo_samples <- linking_allo %>% 
  filter(!is.na(sample_name_prefix) & 
           !(sample_name_prefix %in% linked_allo$sample_name_prefix)) 

length(unique(unlinked_allo_samples$sample_name_prefix))

#Upon visual inspection, the initials in the sample_name_prefix aligns with the letters present in the allozithro_id.

#There should be 5 more to link. 

#This confirms that there are in fact 5 more. We can do so by hand. We also take the minimum age from either dataset to be the observed dataset.
#6

hand_linked_allo <- data.frame("allozithro_id" = 
                                 c("002-1220-M-J",
                                   "002-1108-L-J",
                                   "002-2113-H-B",
                                   "002-2210-S-T",
                                   "002-1103-R-S",
                                   "002-1203-A-E"),
                               "sample_name_prefix" = 
                                 c("MJ345",
                                   "LJ288",
                                   "HB260",
                                   "ST289",
                                   "RS224",
                                   "AE226"))