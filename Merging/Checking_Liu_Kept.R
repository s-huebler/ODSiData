#Checking which liu samples are kept


liu_kept <- data.frame(filtered_meta) %>% 
  filter(study == "Liu")%>%
  select(sample.id, individual)

merged_meta <- read_tsv("~/Documents/ODSi/ODSiData/Merging/merged_metadata.tsv")

liu_all <- merged_meta %>%
  filter(study == "Liu")%>%
  filter(patient == 1)%>%
  filter(age > 18)%>%
  select(sample.id = `sample-id`,
         individual)%>%
  arrange(individual, sample.id)%>%
  group_by(individual)%>%
  mutate(Read1 = sample.id[1],
         Read2 = sample.id[2])%>%
  select(-sample.id)%>%
  distinct()%>%
  ungroup()


assess1 <- liu_kept %>%
  left_join(liu_all,
            by = "individual")%>%
  rowwise()%>%
  mutate(Kept1 = grepl(Read1, sample.id),
         Kept2 = grepl(Read2, sample.id))%>%
  ungroup()%>%
  mutate(Kept = case_when(Kept1 & Kept2 ~ "Both",
                          Kept1 ~ "Read1",
                          Kept2 ~ "Read2"))%>%
  select(sample.id, individual, Kept)
  

